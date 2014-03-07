# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
Sequel.migration do
  change do
    create_table(:email_jobs) do
      primary_key :id
      String :to, :null => false
      String :subject, :null => false
      String :body, :null => false
      String :sent
    end
  end
end
