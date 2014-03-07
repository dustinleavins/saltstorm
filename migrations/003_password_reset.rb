# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
Sequel.migration do
  change do
    create_table(:password_reset_requests) do
      primary_key :id
      String :email, :null => false
      String :code, :null => false
    end
  end
end
