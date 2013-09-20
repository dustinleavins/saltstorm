# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'

require 'uri'
require 'securerandom'
require 'digest'
require 'set'
require 'bundler/setup'
require 'sequel'
require 'yaml'
require './settings.rb'

# Sequel models for Saltstorm
module Models

  # This if block ensures that this file can be required from both app.rb
  # and the 'sequel' command-line utility.
  if (ENV['RACK_ENV'])
    Sequel.connect(Settings::db(ENV['RACK_ENV']))
  end

  # A very simple regular expression for e-mail addresses.
  def self.email_regex
    /\A\S+@\S+\Z/
  end

  # Represents a user
  class User < Sequel::Model
    plugin :validation_helpers

    def before_save
      self.email = self.email.downcase
      super
    end

    def before_validation
      if(!self.password.nil? && !self.password.empty?)
        self.password_salt = User.generate_salt
        self.password_hash = User.generate_password_digest(@password, self.password_salt)
      end
    end
    
    def validate
      super
      validates_presence :email
      validates_format Models.email_regex, :email

      validates_presence :display_name
      validates_presence :balance
      validates_presence :password_hash
      validates_presence :password_salt

      validates_max_length 20, :display_name

      if ((!self.post_url.nil? && !self.post_url.empty?))
        validates_format URI.regexp, :post_url
      end
    end

    # Plain-text representation of password
    def password
      return @password
    end

    # Plain-text representation of password
    def password=(v)
      @password = v
    end

    # Retrieves a Set of permissions
    def permissions
      if !self.permission_entry
        Set.new
      else
        self.permission_entry.split(';').to_set
      end
    end

    # Sets a Set of permissions
    def permissions=(set)
      self.permission_entry = set.to_a.join(';')
    end

    # Generates a digest given a password and hash
    def self.generate_password_digest(password, hash)
      return (Digest::SHA256.new << password << hash ).to_s
    end

    # Generates a random salt value
    def self.generate_salt
      return SecureRandom.base64(8)
    end

    # Retrieves a list containing post_url for all users, excluding empty
    # and null values
    def self.all_post_urls
      return self
        .exclude(:post_url => '')
        .exclude(:post_url => nil)
        .select_map(:post_url)
    end
  end

  # Represents a bet made by a user. Bets are stored temporarily by
  # the system and can only be for the current match.
  class Bet < Sequel::Model
    plugin :validation_helpers

    def before_save
      self.for_participant = self.for_participant.downcase
      super
    end

    def validate
      super

      validates_presence :user_id
      validates_presence :amount
      validates_presence :for_participant
    end

    # User who made this bet.
    # There can only be one user per bet. There can only be one bet per user.
    # This is not a model association because I could not properly express this
    # relationship as a Sequel association.
    def user
      return User.first(id: self.user_id)
    end
  end

  # Represents an email to be sent by the rake task email_job.
  class EmailJob < Sequel::Model
    plugin :validation_helpers

    def validate
      super

      validates_presence [:to, :subject, :body]
      validates_format Models.email_regex, :to
    end
  end

  # Represents a request made to reset a user's password.
  class PasswordResetRequest < Sequel::Model
    plugin :validation_helpers
    def validate
      super
      validates_presence [:email, :code]
      validates_format Models.email_regex, :email
    end

    def before_validation
      self.code ||= SecureRandom.urlsafe_base64
    end
  end
end

