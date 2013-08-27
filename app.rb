# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
require 'yaml'
require 'json'
require 'bigdecimal'
require 'rubygems'
require 'sinatra/base'
require './models.rb'
require './persistence.rb'
require './settings.rb'
include Models

class RootApp < Sinatra::Base

  app_settings = Settings::site(settings.environment.to_s)
  set :static_cache_control, [:private]

  enable :sessions
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

      user = User.first(email: email.downcase)

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

    return erb :signup if User.where(email: @email).count > 0
    return erb :signup if User.where(display_name: @display_name).count > 0

    return erb :signup if (@password != @confirm_password) ||
      @password.nil? || @password.empty?
      @email.nil? || @email.empty? || !(@email.match Models.email_regex) ||
      @display_name.nil? || @display_name.empty?

    user = User.create(email: @email,
                       password: @password,
                       display_name: @display_name,
                       balance: @balance)

    # Send the introductory e-mail at a later time
    EmailJob.create(to: @email,
                    subject: "Welcome to #{app_settings['domain']}!",
                    body: "Welcome to #{app_settings['domain']}, #{@display_name}!")

    session[:uid] = user.id 
    return redirect to('/main')
  end

  post '/login' do
    #@email = params[:email]
    #@password = params[:password]

    #if (@email.nil? || @password.nil?)
    #  return redirect '/login', 303
    #end

    #user = User.first(email: @email.downcase)

    #if user.nil?
    #  return redirect '/login', 303
    #end

    #password_hash = User.generate_password_digest(@password, user.password_salt)

    #if (password_hash != user.password_hash)
    #  return redirect '/login', 303
    #end

    #session[:uid] = user.id
    #return redirect to('/main')
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

    user = User.first(id: session[:uid])
    if user.nil?
      return [500, "{ error: 'Somehow logged-in as fake user'}"]
    end

    return {
      email: user.email,
      balance: user.balance,
      displayName: user.display_name
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

    user = User.first(id: session[:uid])

    if bid_amount > user.balance
      return [500, "{ error: 'insufficient funds'}"]
    end

    existing_bet = Bet.first(user_id: user.id)
    if (existing_bet)
        existing_bet.destroy
    end

    Bet.create(user_id: user.id,
        amount: bid_amount.to_i,
        for_participant: submitted_bid['forParticipant'])

    return [200, "{message: 'ok'}"]
  end

  get '/api/current_match' do
    send_file Persistence::MatchStatusPersistence.match_data_file
  end

  put '/api/current_match' do
    if session[:uid].nil?
      return [500, "{ error: 'Must be logged-in'}"]
    end

    user = User.first(id: session[:uid])
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
      bets_for_a = Bet.where(for_participant: 'a').select_map(:amount)
      new_match_data['participantA']['amount'] = bets_for_a.reduce(:+)

      bets_for_b = Bet.where(for_participant: 'b').select_map(:amount)
      new_match_data['participantB']['amount'] = bets_for_b.reduce(:+)

      if ((bets_for_a.count == 0) || (bets_for_b.count == 0))
        new_match_data[:odds] = '0:0'
      else
        odds = (new_match_data['participantA']['amount'].to_r) / 
          (new_match_data['participantB']['amount'].to_r)

        new_match_data[:odds] = "#{odds.numerator}:#{odds.denominator}"

      end
      all_in_a = Bet.join(User, :id => :user_id)
        .where(for_participant: 'a')
        .where(:amount => :balance)
        .select_map(:display_name)

      all_in_b = Bet.join(User, :id => :user_id)
        .where(for_participant: 'b')
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
    else
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
