# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
Sequel.migration do
  change do
    create_table(:payments) do
      primary_key :id
      foreign_key :user_id, :null => false
      String :payment_type, :null => false
      Integer :amount, :null => false
      String :status, :null => false
      DateTime :date_modified, :null => false
    end
  end
end
