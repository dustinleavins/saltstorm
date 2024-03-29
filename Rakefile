# Saltstorm - Fun-Money Betting on the Web
# Copyright (c) 2013, 2014, 2018 Dustin Leavins
# See the file 'LICENSE.txt' for copying permission
require 'securerandom'
require 'yaml'
require 'fileutils'
require 'bundler/setup'
require 'highline/import'
require 'sequel'
require './persistence.rb'

if ENV['RACK_ENV'].nil?
  ENV['RACK_ENV'] = 'development'
end

task :default do
  puts ENV['RACK_ENV']
end

task :generate_secret_token do
  token_file = 'config/secret_token.yml'
  if (File.exist?(token_file))
    say 'Deleting existing secret token file'
    File.delete(token_file)
  end

  say 'Creating secret token file'
  token = SecureRandom.hex(32)
  File.open(token_file, 'w') do |f|
    f.write("token: #{token}\n")
  end
end

task :reset_match_data do
  say 'Deleting existing match data files'
  if (File.exist? Persistence::MatchStatusPersistence::MATCH_DATA_FILE)
    File.delete Persistence::MatchStatusPersistence::MATCH_DATA_FILE
  end

  say('Initializing non-db persistence')
  Persistence.init_persistence()
end

task :initial_setup do
  if Persistence.has_initialized_persistence?
    say('Initial setup has already been run.')
    next
  end

  Rake::Task['generate_secret_token'].invoke

  if (!File.exist?('config/site.yml'))
    say("Creating 'config/site.yml'")
    FileUtils.cp('config/site.yml.example', 'config/site.yml')
  end

  # Initialize non-db persistence
  say('Initializing non-db persistence')
  Persistence.init_persistence()
  
  # Run db migrations
  say('Running migrations')
  `bundle exec sequel -m migrations -e #{ENV['RACK_ENV']} config/database.yml` 

  db = YAML::load_file('config/database.yml')
  Sequel.connect(db[ENV['RACK_ENV']])
  require './models.rb'
  if ENV['RACK_ENV'] != 'test' && !Models::User.first(:display_name => 'admin')
    # Add admin user if it doesn't already exist
    say('Please enter an e-mail address & password for the admin user')

    email = ask("E-mail address: ") { |q| q.validate = Models.email_regex  }
    password = ask("Password (must be at least 8 characters long): ") do |q|
      q.echo = false 
      q.validate = /.{8,}/
    end

    confirm_password = ask("Confirm Password: ") { |q| q.echo = false }

    if password != confirm_password
      say('Error: Password & Confirm Password do not match')
      say('Please re-run this rake task') 
      return
    end

    # Create user
    Models::User.create(:display_name => 'admin',
        :email => email,
        :password => password, 
        :permission_entry => 'admin',
        :balance => 0)
  end
end

task :email_job do
  require 'mail'
  require './models.rb'

  opt = YAML::load_file('config/email.yml')[ENV['RACK_ENV']]

  Mail.defaults do
    delivery_method opt[:delivery_method], (opt[:options] || {})
  end  

  Models::EmailJob.where(:sent => nil).each do |email_data|
    
    mail_to_send = Mail.new do
      from opt[:from]
      to email_data.to
      subject email_data.subject
      body email_data.body
    end  

    mail_to_send.deliver!

    email_data.sent = 'ok';
    email_data.save
  end

  Models::EmailJob.where(:sent => 'ok').delete
end


