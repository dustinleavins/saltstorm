# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'

require 'json'
require 'fileutils'

# Module containing a static class for non-database persistence.
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
    if (!File.exist?(MatchStatusPersistence.match_data_file))
      MatchStatusPersistence.get_from_file()
    end

  end

  # Persists current match status.
  class MatchStatusPersistence
    @@environment = ENV['RACK_ENV']
    @@match_data_file = "tmp/#{@@environment}/match_data.json"
    @@bet_file = "tmp/#{@@environment}/match_open"

    # Name of file containing match data.
    def self.match_data_file
      return @@match_data_file
    end

    # Retrieves match data from match_data_file.
    # If match_data_file does not exist, this automatically
    # initializes that file before returning its contents.
    def self.get_from_file
      match_data = nil

      if (!File.exist?(@@match_data_file))
        self.save_file({
          :status => 'closed',
          :winner => '',
          :participantA => { :name => '', :amount => 0},
          :participantB => { :name => '', :amount => 0},
          :odds => '',
          :bettors => {
              :a => [],
              :b => [] 
          }
        })

      end

      File.open(@@match_data_file) do |f|
        match_data = JSON.parse(f.readlines.join)
      end

      return match_data
    end

    # Saves match_data to the file.
    def self.save_file(new_match_data)
      File.open(@@match_data_file, 'w') do |f|
        f.write new_match_data.to_json
      end
    end

    # Test to see if bids are currently open.
    def self.bids_open?
      return File.exist?(@@bet_file)
    end

    # Open bids.
    def self.open_bids
      FileUtils.touch @@bet_file
    end

    # Close bids.
    def self.close_bids
      FileUtils.rm @@bet_file, force: true
    end
  end
end

