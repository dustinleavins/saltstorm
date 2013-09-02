ENV['RACK_ENV'] = 'test'

require 'fileutils'
require 'rspec'
require './persistence.rb'
require 'spec_helper'

describe 'Persistence' do
  it 'successfully initializes persistence' do
    # This WILL NOT test what happens if the tmp directory is not present
 
    # Setup
    FileUtils.remove_entry_secure 'tmp/test'

    # Initialize
    Persistence.init_persistence()

    expect(File.exist?('tmp/test/')).to be_true
    expect(File.directory?('tmp/test/')).to be_true
    expect(File.exist?('tmp/test/match_data.json')).to be_true
  end
end

describe 'Persistence::MatchStatusPersistence' do
  it 'allows access to match data' do
    expect(Persistence::MatchStatusPersistence.match_data_file).to eq('tmp/test/match_data.json')

    match_data = Persistence::MatchStatusPersistence.get_from_file
    expect(match_data).to_not be_nil

    match_data['message'] = 'Test Message'
    Persistence::MatchStatusPersistence.save_file(match_data)

    updated_match_data = Persistence::MatchStatusPersistence.get_from_file
    expect(updated_match_data['message']).to eq('Test Message')
  end

  it 'allows bidding to open & close' do
    Persistence::MatchStatusPersistence.open_bids
    expect(Persistence::MatchStatusPersistence.bids_open?).to be_true

    Persistence::MatchStatusPersistence.close_bids
    expect(Persistence::MatchStatusPersistence.bids_open?).to be_false

  end
end

describe 'Persistence::ClientNotifications' do
  it 'allows persistence of client notification' do
    # The current notification should not exist because Persistence testing
    # removes it.
    expect(Persistence::ClientNotifications.current_notification).to be_nil
    expect(File.exist? Persistence::ClientNotifications.current_notification_filename).to be_false

    Persistence::ClientNotifications.current_notification = {
      'data' => 54321
    }

    persisted_notification = Persistence::ClientNotifications.current_notification
    expect(persisted_notification).to_not be_nil
    expect(persisted_notification['data']).to eq(54321)
    expect(persisted_notification['update_id']).to_not be_nil
  end
end

