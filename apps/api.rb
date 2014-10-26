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
require './apps/helpers.rb'
require './models.rb'
require './persistence.rb'
require './settings.rb'
include Models

class ApiApp < Sinatra::Base
  app_settings = Settings::site(settings.environment.to_s)

  configure do
    set :views, 'views/'  #email functionality
    enable :sessions
    register Sinatra::Flash
    set :session_secret, Settings::secret_token

    helpers Helpers
  end

  configure :development, :production do
    enable :logging
  end

  before do
    cache_control :no_cache
  end

  get '/site_config' do
    return json_response(200, {
      :maxRank => app_settings['rankup']['max_rank']
    })
  end

  post '/login' do
    request.body.rewind
    auth_info = JSON.parse(request.body.read)
    if (authenticate(auth_info['email'], auth_info['password']))
      return json_response(200, { :message => 'ok' })
    else
      return json_response(500, { :error => 'invalid login' })
    end
  end

  post '/logout' do
    session[:uid] = nil
    return json_response(200, { :message => 'logged out' })
  end

  post '/register' do
    request.body.rewind
    register_req = JSON.parse(request.body.read)

    @email = CGI::escapeHTML(register_req['email'].downcase)
    password = register_req['password']
    confirm_password = register_req['confirmPassword']
    @display_name = CGI::escapeHTML(register_req['displayName'])
    balance = app_settings['user_signup_balance']

    if (password != confirm_password)
      return json_response(500, { :error => 'Passwords do not match' })
    elsif (User.where(:email => @email).count > 0)
      return json_response(500, { :error => 'Email is not unique' })
    elsif (User.where(:display_name => @display_name).count > 0)
      return json_response(500, { :error => 'Display name is not unique' })
    end

    user = User.new(:email => @email,
                    :password => password,
                    :display_name => @display_name,
                    :balance => balance)

    if (!user.valid?)
      return json_response(500, { :error => user.errors.full_messages.join("\n") });
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
                    :body => erb(:'email/intro', :locals => template_locals, :layout => nil))

    session[:uid] = user.id 
    return json_response(200, { :message => 'ok' })
  end


  get '/account' do
    if (!is_authenticated?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    user = User.first(:id => session[:uid])
    if user.nil?
      return json_response(500, { :error => 'Somehow logged-in as fake user' })
    end

    max_rank = app_settings['rankup']['max_rank']

    if (user.rank == max_rank)
      next_rank_amount = nil # should be unused
    elsif (app_settings['rankup']['amounts'].length < (user.rank + 1))
      next_rank_amount = app_settings['rankup']['amounts'].last
    else
      next_rank_amount = app_settings['rankup']['amounts'][user.rank]
    end

    return json_response(200, {
      :email => user.email,
      :balance => user.balance,
      :displayName => user.display_name,
      :rank => user.rank,
      :amountToNextRank => next_rank_amount
    })
  end

  post '/account/password' do
    if (!is_authenticated?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    request.body.rewind
    edit_req = JSON.parse(request.body.read)

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    password = edit_req['password'].to_s
    confirm_password = edit_req['confirmPassword'].to_s

    if (password.empty? || password != confirm_password)
      return json_response(500, { :error => 'Password error' })
    end

    user.password = password
    user.save()

    return json_response(200, { :message => 'ok' })
  end

  post '/account/info' do
    if (!is_authenticated?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return json_response(500, { :error => 'Must be logged-in' })
    end

    request.body.rewind
    edit_req = JSON.parse(request.body.read)

    # Check password
    password = edit_req['password'].to_s
    password_hash = User.generate_password_digest(password, user.password_salt)

    if (user.password_hash != password_hash)
      return json_response(500, { :error => 'Current password does not match.' })
    end

    user.display_name = edit_req['displayName']
    user.email = edit_req['email']
    user.post_url = edit_req['postUrl']

    if (!user.valid?)
      return json_response(500, { :error => user.errors.full_messages.join("\n") })
    end

    user.save()

    return json_response(200, { :message => 'ok' })
  end

  post '/request_password_reset' do
    request.body.rewind
    reset_req = JSON.parse(request.body.read)

    @email = reset_req['email']

    if (@email.nil?)
      return json_response(500, { :error => 'bad request' })
    end

    @email.downcase!

    user = User.first(:email => @email)

    if user.nil?
      # This behavior might change in the future.
      # For now, just act like invalid requests went through.
      return json_response(200, { :msg => 'ok' })
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
                    :body => erb(:'email/reset_request', :locals => template_locals, :layout => nil))

    return json_response(200, { :msg => 'ok' })
  end


  post '/bet' do
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

  post '/payment' do
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

  post '/send_client_notifications' do
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

  post '/check_client_notification' do
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

  get '/current_match' do
    content_type :json
    return [
      200,
      Persistence::MatchStatusPersistence.get_json
    ]
  end

  put '/current_match' do
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

        new_match_data['participants'].each do |_k, v|
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
        new_match_data['bettors'][participant_key] = betting_users.map do |bettor|
          { 'displayName' => bettor.display_name, 'rank' => bettor.rank }
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
