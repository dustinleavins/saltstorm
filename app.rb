# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
require 'uri'
require 'json'
require 'rubygems'
require 'rest_client'
require 'sinatra/base'
require 'sinatra/flash'
require './models.rb'
require './persistence.rb'
require './settings.rb'
include Models

class RootApp < Sinatra::Base

  app_settings = Settings::site(settings.environment.to_s)
  set :static_cache_control, [:private]

  enable :sessions
  register Sinatra::Flash
  set :session_secret, Settings::secret_token

  helpers do
    def titleize(page_title='')
      if page_title.nil? or page_title.empty?
        return @site_name
      else
        return "#{@site_name} - #{page_title}"
      end
    end

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
  end

  
  before do
      cache_control :private
      @site_name = app_settings['site_name']
      @site_description = app_settings['site_description']
  end

  get '/' do
    return erb :index
  end

  get '/login' do
    return erb :login
  end

  get '/signup' do
    return erb :signup
  end

  post '/signup' do
    @email = params[:email].downcase
    @password = params[:password]
    @confirm_password = params[:confirm_password]
    @display_name = params[:display_name]
    @balance = app_settings['user_signup_balance']

    return erb :signup if User.where(:email => @email).count > 0
    return erb :signup if User.where(:display_name => @display_name).count > 0

    return erb :signup if (@password != @confirm_password) ||
      @password.nil? || @password.empty?
      @email.nil? || @email.empty? || !(@email.match Models.email_regex) ||
      @display_name.nil? || @display_name.empty?

    user = User.create(:email => @email,
                       :password => @password,
                       :display_name => @display_name,
                       :balance => @balance)

    # Send the introductory e-mail at a later time
    EmailJob.create(:to => @email,
                    :subject => "Welcome to #{app_settings['domain']}!",
                    :body => "Welcome to #{app_settings['domain']}, #{@display_name}!")

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

    reset_url = "http://#{app_settings['domain']}/reset_password?" +
      ::URI::encode_www_form([["email", user.email], ["code", reset_request.code]])

    EmailJob.create(:to => @email,
                    :subject => "#{app_settings['domain']} - Password Reset",
                    :body => reset_url)

    @display_name = user.display_name
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
      return redirect to('/request_password_reset')
    else
      return erb :reset_password
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
      return erb :reset_password
    end


    # Update password
    user.password = @new_password
    user.save()

    # Send e-mail notification later
    EmailJob.create(:to => @email,
                    :subject => "#{app_settings['domain']} - Password Reset Successful",
                    :body => "#{user.display_name}, your password was successfully reset")

    # Delete requests for reset
    PasswordResetRequest.where(:email => @email).delete()

    return erb :reset_password_success
  end

  post '/login' do
    if (authenticate(params[:email], params[:password]))
      return redirect to('/main')
    else
      return redirect '/login', 303
    end
  end

  get '/logout' do
    session[:uid] = nil
    return redirect to('/')
  end

  get '/main' do
    if session[:uid].nil?
      return redirect '/login', 303
    end

    @video_link = app_settings['main_video_html']
    return erb :main_page
  end

  get '/account' do
    redirect to('/account/')
  end

  get '/account/' do
    if session[:uid].nil?
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    @display_name = user.display_name
    @email = user.email
    @post_url = user.post_url
    erb :account
  end

  post '/account/info' do
    if (session[:uid].nil?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    # Check password
    password = params[:password].to_s
    password_hash = User.generate_password_digest(password, user.password_salt)

    if (user.password_hash != password_hash)
      flash.next[:info] = { :error_password => true }
      return redirect to('/account/')
    end

    # TODO: Add 'original display_name/email/post_url' in case of error
    @display_name = params[:display_name].to_s
    if (!@display_name.empty?)
      user.display_name = @display_name
    end

    @email = params[:email].to_s
    if (!@email.empty?)
      user.email = @email
    end

    @post_url = params[:post_url].to_s
    if (!@post_url.empty?)
      user.post_url = @post_url
    end

    if (!user.valid?)
      flash.next[:info] = {
        :error_post_url => !(user.errors[:post_url].nil?)
      }

      redirect to('/account/')
    end

    user.save()

    flash.next[:info] = { :success => true }
    redirect to('/account/') 
  end

  post '/account/password' do
    if session[:uid].nil?
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    @password = params[:password].to_s
    @confirm_password = params[:confirm_password].to_s

    if (@password.empty? || @password != @confirm_password)
      flash.next[:password] = { :error_password => true }
      return redirect to('/account/')
    end

    user.password = @password
    user.save()

    @display_name = user.display_name
    @email = user.email
    flash.next[:password] = { :success => true }
    return redirect to('/account/')
  end

  post '/api/login' do
    content_type :json

    request.body.rewind
    auth_info = JSON.parse(request.body.read)
    if (authenticate(auth_info['email'], auth_info['password']))
      return 'ok'.to_json
    else
      return [500, '{error: "invalid login"}']
    end
  end

  get '/api/account' do
    content_type :json

    if session[:uid].nil?
      return [500, "{ error: 'Must be logged-in'}"]
    end

    user = User.first(:id => session[:uid])
    if user.nil?
      return [500, "{ error: 'Somehow logged-in as fake user'}"]
    end

    return {
      :email => user.email,
      :balance => user.balance,
      :displayName => user.display_name
    }.to_json
  end

  post '/api/bet' do
    if !Persistence::MatchStatusPersistence.bids_open?
      return [500, "{ error: 'Cannot bet fun happytime bucks at this time.'}"]
    end

    if session[:uid].nil?
      return [500, "{ error: 'Must be logged-in'}"]
    end
  
    request.body.rewind
    submitted_bid = JSON.parse(request.body.read)
    bid_amount = submitted_bid['amount']

    if ((bid_amount < 1) || (bid_amount.floor != bid_amount))
      return [500, "{error: 'amount must be a positive integer'}"]
    elsif (!['a','b'].include?(submitted_bid['forParticipant']))
      return [500, "{ error: 'invalid request'}"]
    end

    user = User.first(:id => session[:uid])

    if bid_amount > user.balance
      return [500, "{ error: 'insufficient funds'}"]
    end

    existing_bet = Bet.first(:user_id => user.id)
    if (existing_bet)
        existing_bet.destroy
    end

    Bet.create(:user_id => user.id,
        :amount => bid_amount.to_i,
        :for_participant => submitted_bid['forParticipant'])

    return [200, "{message: 'ok'}"]
  end

  post '/api/send_client_notifications' do
    content_type :json

    if (session[:uid].nil?)
      return [500, "{ error: 'Must be logged-in'}"]
    end

    user = User.first(:id => session[:uid])
    if (!user.permissions.include? 'admin')
      return [500, "{ error: 'invalid request'}"]
    end

    request.body.rewind
    update_data = JSON.parse(request.body.read)
   
    Persistence::ClientNotifications.current_notification = update_data

    Thread.new do
      notification_body = Persistence::ClientNotifications.current_notification.to_json

      User.all_post_urls.each do |url|
        begin
          RestClient.post url, notification_body, :content_type => :json
        rescue RestClient::RequestTimeout
          # TODO: Log request failure
        end
      end
    end

    send_file Persistence::ClientNotifications.current_notification_filename
  end

  post '/api/check_client_notification' do
    content_type :json
    request.body.rewind
    notification_to_check = nil

    begin
      notification_to_check = JSON.parse(request.body.read)
    rescue JSON::ParserError
      return [500, '{error: "Request must be in JSON format"}']
    end

    user_provided_id = notification_to_check['update_id']

    if (user_provided_id.nil?)
      return [500, '{error: "Request must include update_id"}']
    end

    update_id = Persistence::ClientNotifications.current_notification['update_id']

    if (user_provided_id != update_id)
      return [500, '{error: "Invalid update_id"}']
    else
      return '{msg: "OK"}'
    end
  end

  get '/api/current_match' do
    send_file Persistence::MatchStatusPersistence.match_data_file
  end

  put '/api/current_match' do
    if session[:uid].nil?
      return [500, "{ error: 'Must be logged-in'}"]
    end

    user = User.first(:id => session[:uid])
    unless user.permissions.include? 'admin'
      return [500, "{ error: 'invalid request'}"]
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
      new_match_data[:bettors] = {
        :a => [],
        :b => [] 
      }

    elsif (old_match_data['status'] == 'open' &&
           new_match_data['status'] == 'inProgress')
      Persistence::MatchStatusPersistence.close_bids
        
      # Calculate amounts & odds
      bets_for_a = Bet.where(:for_participant => 'a').select_map(:amount)
      new_match_data['participantA']['amount'] = bets_for_a.reduce(:+)

      bets_for_b = Bet.where(:for_participant => 'b').select_map(:amount)
      new_match_data['participantB']['amount'] = bets_for_b.reduce(:+)

      if ((bets_for_a.count == 0) || (bets_for_b.count == 0))
        new_match_data[:odds] = '0:0'
      else
        odds = (new_match_data['participantA']['amount'].to_r) / 
          (new_match_data['participantB']['amount'].to_r)

        new_match_data[:odds] = "#{odds.numerator}:#{odds.denominator}"

      end
      all_in_a = Bet.join(User, :id => :user_id)
        .where(:for_participant => 'a')
        .where(:amount => :balance)
        .select_map(:display_name)

      all_in_b = Bet.join(User, :id => :user_id)
        .where(:for_participant => 'b')
        .where(:amount => :balance)
        .select_map(:display_name)

      new_match_data[:bettors] = {
        :a => all_in_a,
        :b => all_in_b
      }

    elsif (old_match_data['status'] == 'inProgress' &&
           new_match_data['status'] == 'payout')
      payout = true

    elsif (old_match_data['status'] == 'payout' &&
           new_match_data['status'] == 'closed')
      # payout -> closed transition is internal
      return [500, "{error: 'Cannot manually transition from payout to closed status'}"]

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
      new_match_data[:bettors] = {
        :a => [],
        :b => [] 
      }

    # No other status transitions are allowed
    elsif (old_match_data['status'] != new_match_data['status'])
      return [500, "{error: 'invalid request'}"]
    end

    # Save status
    Persistence::MatchStatusPersistence.save_file(new_match_data)

    if payout
      Thread.new do
        match_data = Persistence::MatchStatusPersistence.get_from_file

        winner = match_data['winner'].downcase
  
        odds_winner = winner == 'a' ? 'participantA' : 'participantB'
        odds_loser = winner != 'a' ? 'participantA' : 'participantB'

        amount_winner = (match_data[odds_winner]['amount'].to_r)
        amount_loser = (match_data[odds_loser]['amount'].to_r)

        if (amount_winner != 0.to_r && amount_loser != 0.to_r)
          odds = amount_loser / amount_winner

          Bet.all.each do |bet|
            user = bet.user

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

    return [200, "{message: 'OK'}"]
  end
end
