# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
Sequel.migration do
  change do
    alter_table(:users) do
      add_column :post_url, String
    end
  end
end
