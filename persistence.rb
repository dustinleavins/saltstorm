# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'

require 'securerandom'
require 'json'
require 'fileutils'
require 'pstore'

# Module containing 'static' classes for non-database persistence.
module Persistence
  
  # Initializes non-database persistence.
  # This initialization only needs to occur once as part of initial
  # app setup, so users of the Persistence module probably do not
  # need to call this method.
  def self.init_persistence()
    # Initialize tmp directory
    if File.exist?('tmp') && !File.directory?('tmp')
      throw "Please delete 'tmp' file"
    elsif !File.exist? 'tmp'
      FileUtils.mkdir 'tmp'
    end

    # Initialize environment-specific directory
    environment_dir = "tmp/#{ENV['RACK_ENV']}"

    if File.exist?(environment_dir) && !File.directory?(environment_dir)
      throw "Please delete '#{environment_dir}' file"
    elsif !File.exist? environment_dir
      FileUtils.mkdir environment_dir
    end

    # Initialize match_data
    if (!File.exist?(MatchStatusPersistence::MATCH_DATA_FILE))
      MatchStatusPersistence.save_file({
        :status => 'closed',
        :winner => '',
        :participants => {
          'a' => { :name => '', :amount => 0, :odds => ''},
          'b' => { :name => '', :amount => 0, :odds => ''}
        },
        :message => '',
        :bettors => {
          :a => [],
          :b => [] 
        }
      })
    end
  end

  # Persists current match status.
  class MatchStatusPersistence

    # Name of file containing match data.
    MATCH_DATA_FILE = "tmp/#{ENV['RACK_ENV']}/match_data.pstore"

    # Retrieves match data from match_data_file.
    def self.get_from_file
      return JSON.parse(self.get_json)
    end

    # Retrieves match data in JSON format
    def self.get_json
      store = PStore.new(MATCH_DATA_FILE)
      return store.transaction do
        store[:match_data]
      end

      #return File.open(MATCH_DATA_FILE) do |f|
      #  f.readlines.join
      #end
    end

    # Saves match_data to the file.
    def self.save_file(new_match_data)
      #File.open(MATCH_DATA_FILE, 'w') do |f|
      #  f.write new_match_data.to_json
      #end
      store = PStore.new(MATCH_DATA_FILE)
      store.transaction do
        store[:match_data] = new_match_data.to_json
      end
    end

    # Test to see if bids are currently open.
    def self.bids_open?
      store = PStore.new(MATCH_DATA_FILE)
      return store.transaction do
        !store[:bets_open].nil? && store[:bets_open]
      end
    end

    # Open bids.
    def self.open_bids
      store = PStore.new(MATCH_DATA_FILE)
      store.transaction do
        store[:bets_open] = true
      end
    end

    # Close bids.
    def self.close_bids
      store = PStore.new(MATCH_DATA_FILE)
      store.transaction do
        store[:bets_open] = false
      end
    end
  end

  # Persists the most recent notification made by an admin to web clients.
  class ClientNotifications

    # Name of the file containing the most recent notification.
    NOTIFY_FILENAME = "tmp/#{ENV['RACK_ENV']}/current_notification.json"
    
    # Hash containing data from the most recent notification.
    def self.current_notification
      notification_data = nil

      if (File.exist? NOTIFY_FILENAME)
        File.open(NOTIFY_FILENAME, 'r') do |f|
          notification_data = JSON.parse(f.readlines.join)
        end
      end

      return notification_data
    end

    # Create a new notification to be sent to clients.
    def self.current_notification=(hash_with_data)
      save_hash = hash_with_data.clone
      save_hash[:update_id] = SecureRandom.base64(8)
      File.open(NOTIFY_FILENAME, 'w') do |f|
        f.write(save_hash.to_json)
      end
    end
  end
end

