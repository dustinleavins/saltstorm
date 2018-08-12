# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014, 2018  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'

require 'date'
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

  # Generates a digest
  def self.generate_digest(contents, salt)
    return (Digest::SHA256.new << contents << salt ).to_s
  end

  # Generates a random salt value
  def self.generate_salt
    return SecureRandom.base64(8)
  end

  # Represents a user
  class User < Sequel::Model
    plugin :validation_helpers
    one_to_many :payments
    one_to_many :api_keys

    # Hash of lambdas that return arrays of betting Users.
    GetBettorsStrategies = {
      'all_in' => lambda do |for_participant|
        User.join(Bet.dataset, :user_id => :id)
          .where(:for_participant => for_participant)
          .where(:amount => :balance)
          .all
      end,

      'all_bettors' => lambda do |for_participant|
        User.join(Bet.dataset, :user_id => :id)
          .where(:for_participant => for_participant)
          .all
      end
    }

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

      validates_presence [:display_name, :balance, :password_hash,
        :password_salt]

      validates_max_length 20, :display_name

      validates_integer :balance
      validates_integer :rank unless rank.nil? # rank can be nil during validation

      if (balance && balance.to_i < 0)
        errors.add(:balance,
                   'Balance cannot be below 0 for any user')
      end

      if ((!self.post_url.nil? && !self.post_url.empty?))
        validates_format URI.regexp, :post_url
      end
    end

    # Plain-text representation of password
    # Do not depend on this to be non-nil for users that are already
    # logged-in.
    attr_accessor :password

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

    # Gets an array of users betting on 'for_participant' using
    # the specified method string.
    def self.get_bettors(for_participant, method)
      GetBettorsStrategies[method].call(for_participant)
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

  # Represents a fun-money payment made by a user
  class Payment < Sequel::Model
    plugin :validation_helpers
    many_to_one :user

    def before_save
      self.date_modified = DateTime.now
      super
    end

    def validate
      super
      validates_presence [:user_id, :payment_type, :amount, :status]

      valid_statuses = ['pending', 'complete']
      valid_types = ['rankup']

      if (!(valid_statuses.member? status))
        errors.add(:status, 'invalid status')
      end

      if (new? && !user.nil? && amount.to_i > user.balance)
        errors.add(:amount,
                   'Amount cannot be higher than user\'s balance for new Payment ' +
                   "amount: #{amount} balance: #{user.balance}")
      end

      if (amount && amount.to_i <= 0)
        errors.add(:amount,
                   "Amount cannot be 0 or negative.")
      end

      if (!(valid_types.member? payment_type))
        errors.add(:payment_type,
                   'Unsupported payment type')
      end
    end
  end

  # Represents an API key
  class ApiKey < Sequel::Model
    plugin :validation_helpers
    many_to_one :user

    # Plain-text representation of key
    attr_accessor :key

    def before_save
      self.date_modified = DateTime.now
      super
    end

    def before_validation
      if(!self.key.nil? && !self.key.empty?)
        self.key_salt = Models.generate_salt()
        self.key_hash = Models.generate_digest(@key, self.key_salt)
      end
    end

    def validate
      super
      validates_presence [:user_id, :key_salt, :key_hash]
    end

    def full_key
      if self.key.nil? || self.key.empty? || self.user_id.nil?
        return nil
      end

      return "#{self.user_id}#{Models::ApiKey.key_separator}#{self.key}"
    end

    def self.new_with_random_key(args)
      args[:key] = SecureRandom.base64(12)
      return self.new(args)
    end

    # Character separating user id and key in an ApiKey's full key.
    def self.key_separator
      return '+'
    end
  end
end
