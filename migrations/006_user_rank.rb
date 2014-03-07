# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
Sequel.migration do
  change do
    alter_table(:users) do
      add_column :rank, Integer, :default => 0, :null => false
    end
  end
end
