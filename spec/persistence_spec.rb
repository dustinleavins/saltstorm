ENV['RACK_ENV'] = 'test'

require 'spec_helper'
require 'fileutils'
require 'rspec'
require './persistence.rb'

describe 'Persistence' do
  it 'successfully initializes persistence' do
    # This WILL NOT test what happens if the tmp directory is not present
 
    # Setup
    FileUtils.remove_entry_secure 'tmp/test'

    # Initialize
    Persistence.init_persistence()

    expect(File.exist?('tmp/test/')).to be_truthy
    expect(File.directory?('tmp/test/')).to be_truthy
    expect(File.exist?('tmp/test/match_data.pstore')).to be_truthy
  end
end

describe 'Persistence::MatchStatusPersistence' do
  it 'allows access to match data' do
    reset_match_data

    expect(Persistence::MatchStatusPersistence::MATCH_DATA_FILE).to eq('tmp/test/match_data.pstore')

    match_data = Persistence::MatchStatusPersistence.get_from_file
    expect(match_data).to_not be_nil

    match_data['message'] = 'Test Message'
    Persistence::MatchStatusPersistence.save_file(match_data)

    updated_match_data = Persistence::MatchStatusPersistence.get_from_file
    expect(updated_match_data['message']).to eq('Test Message')
  end

  it 'allows bidding to open & close' do
    reset_match_data

    Persistence::MatchStatusPersistence.open_bids
    expect(Persistence::MatchStatusPersistence.bids_open?).to be_truthy

    Persistence::MatchStatusPersistence.close_bids
    expect(Persistence::MatchStatusPersistence.bids_open?).to be_falsy

  end
end

describe 'Persistence::ClientNotifications' do
  it 'allows persistence of client notification' do
    # The current notification should not exist because Persistence testing
    # removes it.
    expect(Persistence::ClientNotifications.current_notification).to be_nil
    expect(File.exist? Persistence::ClientNotifications::NOTIFY_FILENAME).to be_falsy

    Persistence::ClientNotifications.current_notification = {
      'data' => 54321
    }

    persisted_notification = Persistence::ClientNotifications.current_notification
    expect(persisted_notification).to_not be_nil
    expect(persisted_notification['data']).to eq(54321)
    expect(persisted_notification['update_id']).to_not be_nil
  end
end

