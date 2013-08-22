# Saltstorm - 'Fun-Money' Betting on the Web
# Copyright (C) 2013  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'

require 'securerandom'
require 'digest'
require 'set'
require 'bundler/setup'
require 'sequel'
require 'yaml'

module Models
  if (ENV['RACK_ENV'])
    Sequel.connect(YAML::load_file('config/database.yml')[ENV['RACK_ENV']])
  end

  def self.email_regex
    /\A\S+@\S+\Z/
  end

  class User < Sequel::Model
    plugin :validation_helpers

    def before_save
      self.email = self.email.downcase
      super
    end

    def before_validation
      self.password_salt ||= User.generate_salt
      self.password_hash ||= User.generate_password_digest(@password, self.password_salt)
    end
    
    def validate
      super
      validates_presence :email
      validates_format Models.email_regex, :email

      validates_presence :display_name
      validates_presence :balance
      validates_presence :password_hash
      validates_presence :password_salt
    end

    def password
      return @password
    end

    def password=(v)
      @password = v
    end

    def permissions
      if !self.permission_entry
        Set.new
      else
        self.permission_entry.split(';').to_set
      end
    end

    def permissions=(set)
      self.permission_entry = set.to_a.join(';')
    end

    def self.generate_password_digest(password, hash)
      return (Digest::SHA256.new << password << hash ).to_s
    end

    def self.generate_salt
      return SecureRandom.base64(8)
    end
  end

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

    def user
      return User.first(id: self.user_id)
    end
  end
end
