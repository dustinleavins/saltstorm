# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
Sequel.migration do
  change do
    create_table(:users) do
      primary_key :id
      String :email, :null => false, :unique => true
      String :password_hash, :null => false
      String :password_salt, :null => false
      Integer :balance, :null => false
      String :display_name, :null => false, :unique => true
      String :permission_entry
    end

    create_table(:bets) do
      primary_key :id
      foreign_key :user_id, :null => false
      Integer :amount, :null => false
      String :for_participant, :size=> 1, :fixed => true, :null => false
    end
  end
end
