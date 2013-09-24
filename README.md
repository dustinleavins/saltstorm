# Saltstorm - Fun-Money Betting on the Web

## What is Saltstorm?
Saltstorm is an open-source clone of [Salty Bet](http://www.saltybet.com) built with Ruby.

## Deployment
You must have shell access on your web server and the ability to run Rack web apps. Initial setup is a seven-step process:

1. Put the files on your server and run `bundle install`
2. Create and setup your database of choice (currently supports Postgre and SQLite)
3. Create a config/database.yml file to provide DB connection details
4. Create a config/email.yml file for sending emails to users
5. Run `rake initial_setup`
6. Tweak config/site.yml to your liking
7. Setup important cron jobs using `bundle exec whenever` ([official site for whenever](https://github.com/javan/whenever))

The Gemfile includes the 'thin' gem. But you can probably deploy it using anything (please don't use WEBrick). I'll try to add MySQL gems in the future.

## Saltstorm is a WIP
Saltstorm is unstable and has no version number. I hope that nothing breaks, but it could!

## License Info
AGPL3.

## Saltstorm Uses Cool Technologies
I built Saltstorm with Sinatra (with sinatra-flash) and Sequel. The Rakefile uses Highline for user input. whenever makes the cron job for sending e-mails. mail sends e-mails. RestClient POSTs data to web users. 

The front-end uses jQuery, AngularJS, and  Bootstrap 3.0. Javascript & CSS are pulled from CDNs provided by Google and [Bootstrap CDN](http://bootstrapcdn.com).

Tests use rspec, rack-test, factory\_girl, and simplecov.

