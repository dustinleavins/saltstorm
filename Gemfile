source "https://rubygems.org"
gem "rake"
gem "sinatra"
gem "sinatra-flash"
gem "sinatra-asset-pipeline", :require => false
gem "sass"
gem "highline"
gem "sequel"
gem "mail"
gem "whenever", :require => false
gem "rest-client"

group :test do
  gem "rspec", :require => false
  gem "rack-test", :require => false
  gem "factory_bot", :require => false
  gem "simplecov", :require => false
  gem "rubocop", :require => false
end

group :sqlite3 do
  gem "sqlite3", :require => false, :platforms => :ruby
  gem "jdbc-sqlite3", :require => false, :platforms => :jruby
end

#group :pg do
#  gem "pg", :require => false, :platforms => :ruby
#  gem "jdbc-postgres", :require => false, :platforms => :jruby
#end

#group :mysql do
#  gem "mysql2", :require => false, :platforms => :ruby
#  gem "jdbc-mysql", :require => false, :platforms => :jruby
#end

group :thin do
  gem "thin", :require => false, :platforms => :ruby
end

