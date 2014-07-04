# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
require 'uri'
require 'cgi'
require 'json'
require 'rubygems'
require 'bundler'
Bundler.require
require 'sinatra/asset_pipeline'
require './apps/helpers.rb'
require './models.rb'
require './persistence.rb'
require './settings.rb'
include Models

class MainApp < Sinatra::Base
  app_settings = Settings::site(settings.environment.to_s)
  
  configure do
    set :views, 'views/' 
    set :static_cache_control, [:private]
    set :public_folder, './public/'

    enable :sessions
    register Sinatra::Flash
    set :session_secret, Settings::secret_token

    register Sinatra::AssetPipeline

    helpers Helpers
  end

  configure :development, :production do
    enable :logging
  end

  helpers do
    def authenticate(email, password)
      if (email.nil? || password.nil?)
        return nil
      end

      user = User.first(:email => email.downcase)

      if user.nil?
        return nil
      end

      password_hash = User.generate_password_digest(password, user.password_salt)

      if (password_hash != user.password_hash)
        return nil
      end

      session[:uid] = user.id
      return 'ok'
    end

    def is_authenticated?
      return !(session[:uid].nil?)
    end
  end
  
  
  before '/api/*' do
    cache_control :no_cache
    @api = true
  end

  before do
      if !@api
        cache_control :private
        @site_name = app_settings['site_name']
        @site_description = app_settings['site_description']
      end
  end

  get '/' do
    return erb :index
  end
 
  get '/login' do
    return erb :login
  end

  post '/login' do
    auth_ok = authenticate(params[:email], params[:password])

    if (auth_ok && params[:mobile])
      redirect to('/main_mobile')
    elsif (auth_ok)
      redirect to('/main')
    else
      flash.next[:error] = true
      redirect to('/login'), 303
    end
  end

  get '/signup' do
    return erb :signup
  end

  post '/signup' do
    @email = CGI::escapeHTML(params[:email].downcase)
    password = params[:password]
    confirm_password = params[:confirm_password]
    @display_name = CGI::escapeHTML(params[:display_name])
    balance = app_settings['user_signup_balance']

    if (password != confirm_password)
      flash.now[:error] = { :password => true }
      return erb :signup
    elsif (User.where(:email => @email).count > 0)
      flash.now[:error] = { :email_not_unique => true }
      return erb :signup
    elsif (User.where(:display_name => @display_name).count > 0)
      flash.now[:error] = { :display_name_not_unique => true }
      return erb :signup
    end

    user = User.new(:email => @email,
                    :password => password,
                    :display_name => @display_name,
                    :balance => balance)

    if (!user.valid?)
      flash.now[:error] = user.errors
      return erb :signup
    end

    user.save()

    # Send the introductory e-mail at a later time
    site_url = app_settings['site_url']
    template_locals = {
      :site_url => site_url,
      :display_name => user.display_name,
      :email => user.email,
      :balance => user.balance 
    }

    EmailJob.create(:to => @email,
                    :subject => "Welcome to #{site_url}!",
                    :body => erb(:'email/intro', :locals => template_locals))

    session[:uid] = user.id 
    return redirect to('/main')
  end

  get '/request_password_reset' do
    return erb :request_password_reset
  end

  post '/request_password_reset' do
    @email = params[:email]

    if (@email.nil?)
      return erb :request_password_reset
    end

    @email.downcase!

    user = User.first(:email => @email)

    if user.nil?
      # This behavior might change in the future.
      # For now, just act like invalid requests went through.
      return erb :request_password_reset_success
    end

    reset_request = PasswordResetRequest.create(:email => @email)

    @reset_url = ::URI.join(app_settings['site_url'], '/reset_password').to_s +
        ::URI::encode_www_form([["email", user.email], ["code", reset_request.code]])

    @site_url = app_settings['site_url']

    template_locals = {
      :site_url => @site_url,
      :reset_url => @reset_url,
      :display_name => user.display_name
    }

    EmailJob.create(:to => @email,
                    :subject => "#{@site_url} - Password Reset",
                    :body => erb(:'email/reset_request', :locals => template_locals))

    return erb :request_password_reset_success
  end

  get '/reset_password' do
    @email = params[:email]
    @code = params[:code]

    if (@email.nil? || @code.nil?)
      return redirect to('/request_password_reset')
    end

    reset_request = PasswordResetRequest.first(:email => @email, :code => @code)
    if (reset_request.nil?)
      redirect to('/request_password_reset')
    else
      erb :reset_password
    end
 end

  post '/reset_password' do
    @email = params[:email].to_s.downcase
    @code = params[:code].to_s
    @new_password = params[:password].to_s
    @confirm_new_password = params[:confirm_password].to_s
    
    reset_request = PasswordResetRequest.first(:email => @email, :code => @code)
    if (reset_request.nil?)
      # /reset_password view has an error in it
      return 500
    end

    user = User.first(:email => @email)
    if (user.nil?)
      return 500
    end

    if (@email.empty? || @code.empty? ||
        @new_password.empty? || @new_password != @confirm_new_password)
      # Something's wrong; it's likely an invalid password
      flash.now[:error] = true
      return erb :reset_password
    end

    # Update password
    user.password = @new_password
    user.save()

    # Send e-mail notification later
    @site_url = app_settings['site_url']

    template_locals = {
      :display_name => user.display_name,
      :site_url => @site_url
    }

    EmailJob.create(:to => @email,
                    :subject => "#{@site_url} - Password Reset Successful",
                    :body => erb(:'email/password_changed', :locals => template_locals))

    # Delete requests for reset
    PasswordResetRequest.where(:email => @email).delete()

    @display_name = user.display_name
    return erb :reset_password_success
  end

  get '/logout' do
    session[:uid] = nil
    return redirect to('/')
  end

  get '/main' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    @video_link = app_settings['main_video_html']
    @bettors_strategy = app_settings['bettors_show']
    return erb :main_page
  end

  get '/main_mobile' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    return erb :main_page_mobile
  end

  get '/account' do
    redirect to('/account/')
  end

  get '/account/' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    @original = {
      :display_name => CGI::escapeHTML(user.display_name),
      :email => CGI::escapeHTML(user.email),
      :post_url => CGI::escapeHTML(user.post_url.to_s) # post_url might be nil
    }

    @current = flash[:current] || @original
    erb :account
  end

  post '/account/info' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    # Check password
    password = params[:password].to_s
    password_hash = User.generate_password_digest(password, user.password_salt)

    flash.next[:current] = {
      :display_name => CGI::escapeHTML(params[:display_name].to_s),
      :email => CGI::escapeHTML(params[:email].to_s),
      :post_url => CGI::escapeHTML(params[:post_url].to_s)
    }

    if (user.password_hash != password_hash)
      flash.next[:info] = { :error => {:password => true } }
      return redirect to('/account/')
    end

    user.display_name = flash.next[:current][:display_name]
    user.email = flash.next[:current][:email]
    user.post_url = flash.next[:current][:post_url]

    if (!user.valid?)
      error_info = {
        :display_name =>  !(user.errors[:display_name].nil?),
        :email =>  !(user.errors[:email].nil?),
        :post_url => !(user.errors[:post_url].nil?)
      }

      flash.next[:info] = { :error => error_info }

      redirect to('/account/')
    end

    user.save()

    flash.next[:info] = { :success => true }
    redirect to('/account/') 
  end

  post '/account/password' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    password = params[:password].to_s
    confirm_password = params[:confirm_password].to_s

    if (password.empty? || password != confirm_password)
      flash.next[:password] = { :error => true }
      return redirect to('/account/')
    end

    user.password = password
    user.save()

    flash.next[:password] = { :success => true }
    return redirect to('/account/')
  end

  get '/payments' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    @current_rank = user.rank
    @max_rank = app_settings['rankup']['max_rank']

    if (@current_rank == @max_rank)
      @next_rank_amount = nil # should be unused
    elsif (app_settings['rankup']['amounts'].length < (@current_rank + 1))
      @next_rank_amount = app_settings['rankup']['amounts'].last
    else
      @next_rank_amount = app_settings['rankup']['amounts'][@current_rank]
    end

    erb :payments
  end


  post '/api/login' do
    request.body.rewind
    auth_info = JSON.parse(request.body.read)
    if (authenticate(auth_info['email'], auth_info['password']))
      return json_response(200, { :message => 'ok' })
    else
      return json_response(500, { :error => 'invalid login' })
    end
  end

  get '/api/account' do
    if (!is_authenticated?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    user = User.first(:id => session[:uid])
    if user.nil?
      return json_response(500, { :error => 'Somehow logged-in as fake user' })
    end

    return json_response(200, {
      :email => user.email,
      :balance => user.balance,
      :displayName => user.display_name
    })
  end

  post '/api/bet' do
    if !Persistence::MatchStatusPersistence.bids_open?
      return json_response(500, { :error => 'Cannot bet fun happytime bucks at this time.' }) 
    end

    if (!is_authenticated?)
      return json_response(500, { :error => 'Must be logged-in' })
    end
  
    request.body.rewind
    submitted_bid = JSON.parse(request.body.read)
    bid_amount = submitted_bid['amount'] || 0

    participant_keys = Persistence::MatchStatusPersistence
      .get_from_file['participants'].keys

    if ((bid_amount < 1) || (bid_amount.floor != bid_amount))
      return json_response(500, { :error => 'amount must be a positive integer' })
    elsif (!participant_keys.include?(submitted_bid['forParticipant']))
      return json_response(500, { :error => 'invalid request' })
    end

    user = User.first(:id => session[:uid])

    if bid_amount > user.balance
      return json_response(500, { :error => 'insufficient funds' })
    end

    existing_bet = Bet.first(:user_id => user.id)
    if (existing_bet)
        existing_bet.destroy
    end

    Bet.create(:user_id => user.id,
        :amount => bid_amount.to_i,
        :for_participant => submitted_bid['forParticipant'])

    return json_response(200, { :message => 'ok'})
  end

  post '/api/payment' do
    if (!is_authenticated?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    if (Bet.where(:user_id => session[:uid]).count > 0)
      return json_response(500, { :error => 'Cannot make payment while betting'})
    end

    request.body.rewind
    user_payment_info = JSON.parse(request.body.read)

    user = User.first(:id => session[:uid])
   
    payment = Payment.new(
      :user => user,
      :payment_type => user_payment_info['payment_type'],
      :amount => user_payment_info['amount'],
      :status => 'pending'
    )

    if (!payment.valid?)
      return json_response(500, { :error => 'Invalid payment details\n' + payment.errors.to_json})
    end

    payment.save

    previous_balance = user.balance
    if (user.balance > payment.amount)
      user.balance -= payment.amount
    else # user wants to go broke on a payment
      user.balance = app_settings['base_bailout_balance']
    end
    
    user.save

    # 'rankup' processing
    if (user.rank == app_settings['rankup']['max_rank'])
      # already at max rank
      user.balance = previous_balance
      user.save
      payment.delete
      return json_response(500, { :error => 'Already at maximum rank' })
    end

    requested_rank = user.rank + 1

    rankup_amount = nil
    if (app_settings['rankup']['amounts'].length < requested_rank)
      rankup_amount = app_settings['rankup']['amounts'].last
    else
      rankup_amount = app_settings['rankup']['amounts'][requested_rank - 1]
    end

    if (payment.amount != rankup_amount)
      user.balance = previous_balance
      user.save
      payment.delete
      return json_response(500, { :error => 'Invalid amount for rankup' })
    end

    user.rank = requested_rank
    user.save
    
    payment.status = 'complete'
    payment.save

    return json_response(200, { :message => 'ok' })
  end

  post '/api/send_client_notifications' do
    if (!is_authenticated?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    user = User.first(:id => session[:uid])
    if (!user.permissions.include? 'admin')
      return json_response(500, { :error => 'invalid request' })
    end

    request.body.rewind
    update_data = JSON.parse(request.body.read)
   
    Persistence::ClientNotifications.current_notification = update_data

    Thread.new do
      notification_body = Persistence::ClientNotifications.current_notification.to_json

      User.all_post_urls.each do |url|
        begin
          RestClient.post url, notification_body, :content_type => :json
        rescue RestClient::Exception
          logger.error "Cannot push client notification to '#{url}' - #{$!}"
        end
      end
    end

    send_file Persistence::ClientNotifications::NOTIFY_FILENAME
  end

  post '/api/check_client_notification' do
    request.body.rewind
    notification_to_check = nil

    begin
      notification_to_check = JSON.parse(request.body.read)
    rescue JSON::ParserError
      return json_response(500, { :error => 'Request must be in JSON format' })
    end

    user_provided_id = notification_to_check['update_id']

    if (user_provided_id.nil?)
      return json_response(500, { :error => 'Request must include update_id' })
    end

    update_id = Persistence::ClientNotifications.current_notification['update_id']

    if (user_provided_id != update_id)
      return json_response(500, { :error => 'Invalid update_id' })
    else
      return json_response(200, { :message => "OK" })
    end
  end

  get '/api/current_match' do
    send_file Persistence::MatchStatusPersistence::MATCH_DATA_FILE
  end

  put '/api/current_match' do
    if (!is_authenticated?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    user = User.first(:id => session[:uid])
    unless user.permissions.include? 'admin'
      return json_response(500, { :error => 'invalid request' })
    end
  
    old_match_data = Persistence::MatchStatusPersistence.get_from_file

    # The admin of the site should be trusted not 
    # crash the server (at least for now)
    request.body.rewind
    new_match_data = JSON.parse(request.body.read)

    payout = nil

    # Normal match status transitions:
    # closed -> open -> inProgress -> payout
    if (old_match_data['status'] == 'closed' &&
        new_match_data['status'] == 'open')
      Persistence::MatchStatusPersistence.open_bids

      # Reset bettors lists
      new_match_data['bettors'] = {
        :a => [],
        :b => [] 
      }

      # Reset participant info
      new_match_data['participants'].values.each do |p|
        p['odds'] = ''
        p['amount'] = 0
      end
    elsif (old_match_data['status'] == 'open' &&
           new_match_data['status'] == 'inProgress')
      Persistence::MatchStatusPersistence.close_bids
        
      # Calculate amounts & odds
      new_match_data['participants'].each do |k, v|
        v['amount'] = Bet
          .where(:for_participant => k)
          .select_map(:amount)
          .reduce(:+)
      end

      parts_with_bets = new_match_data['participants'].values.count do |p|
        p['amount'] != nil && p['amount'] > 0
      end

      if (parts_with_bets < 2)
        new_match_data['participants'].values.each do |p|
          p['odds'] = "0:0"
        end
      else
        total = new_match_data['participants'].values.inject(0) do |sum, p|
          sum + p['amount'].to_i # might be nil
        end

        new_match_data['participants'].each do |k, v|
          if v['amount'] == nil
            v['odds'] = '0:0'
          else
            other_total = total - v['amount'].to_r
            odds = (v['amount'].to_r) / (other_total.to_r)
            v['odds'] = "#{odds.numerator}:#{odds.denominator}"
          end
        end
      end

      new_match_data['bettors'] = {}
      new_match_data['participants'].keys.each do |participant_key|
        betting_users = User.get_bettors(participant_key, app_settings['bettors_show'])
        new_match_data['bettors'][participant_key] = betting_users.map do |user|
          { 'displayName' => user.display_name, 'rank' => user.rank }
        end
      end

    elsif (old_match_data['status'] == 'inProgress' &&
           new_match_data['status'] == 'payout')
      payout = true

    elsif (old_match_data['status'] == 'payout' &&
           new_match_data['status'] == 'closed')
      # payout -> closed transition is internal
      return json_response(500, { :error => 'Cannot manually transition from payout to closed status' })

    # Non-normal status transition: inProgress -> closed
    # Represents 'match cancellation' during match
    elsif (old_match_data['status'] == 'inProgress' &&
           new_match_data['status'] == 'closed')
      # Clear bets
      Bet.where().destroy

      # Reset bettors lists
      new_match_data[:bettors] = {
        :a => [],
        :b => [] 
      }
    
    # Non-normal status transition: open -> closed
    # Represents 'match cancellation' before match
    elsif (old_match_data['status'] == 'open' &&
           new_match_data['status'] == 'closed')
      Persistence::MatchStatusPersistence.close_bids
      Bet.where().destroy

      # Reset bettors lists
      new_match_data['bettors'] = {
        'a' => [],
        'b' => [] 
      }

    # No other status transitions are allowed
    elsif (old_match_data['status'] != new_match_data['status'])
      return json_response(500, { :error => 'invalid request' })
    end

    # Save status
    Persistence::MatchStatusPersistence.save_file(new_match_data)

    if payout
      Thread.new do
        match_data = Persistence::MatchStatusPersistence.get_from_file

        winner = match_data['winner'].downcase
  
        amount_winner = 0
        amount_loser = 0

        if (winner != 'tie')
          odds_winner = winner
 
          # amount for winner might be nil
          amount_winner = (match_data['participants'][winner]['amount']).to_i

          total = new_match_data['participants'].values.inject(0) do |sum, p|
            sum + p['amount'].to_i # might be nil
          end

          amount_loser = total - amount_winner
        end

        # Skip payout if:
        # at least one participant did not have any bettors
        #   -or-
        # match ended in a tie
        if (amount_winner != 0 && amount_loser != 0)
          odds = amount_loser.to_r / amount_winner.to_r

          Bet.all.each do |bet|
            user = bet.user

            if user.balance < bet.amount
              # It is possible for the user, by manipulating payments and
              # betting, to be in a state where bet amount exceeds
              # account balance.
              #
              # Just ignore these bets!
              next
            end

            if bet.for_participant.downcase == winner
              user.balance += (bet.amount * odds).ceil
            elsif user.balance > bet.amount
              user.balance -= bet.amount
            else # user lost all of their money
              user.balance = app_settings['base_bailout_balance']
            end

            user.save
          end
        end

        Bet.where().destroy

        match_data['status'] = 'closed'

        Persistence::MatchStatusPersistence.save_file(match_data)
      end
    end

    return json_response(200, { :message => 'OK' })
  end
end
