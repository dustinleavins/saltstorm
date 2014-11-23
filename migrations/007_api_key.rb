# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
Sequel.migration do
  change do
    create_table(:api_keys) do
      primary_key :id
      foreign_key :user_id, :null => false
      String :key_hash, :null => false
      String :key_salt, :null => false
      DateTime :date_modified, :null => false
    end
  end
end

