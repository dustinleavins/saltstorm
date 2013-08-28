# Saltstorm - Fun-Money Betting on the Web

## What is Saltstorm?
Saltstorm is an open-source clone of [Salty Bet](http://www.saltybet.com) built with Ruby.

## Deployment
You must have shell access on your web server and the ability to run Rack web apps. Currently, initial setup is a five-step process:

1. Put the files on your server and run `bundle install`
2. Create your database & set it up (if not using SQLite)
3. Create an config/database.yml (example is provided)
4. Setup cron jobs using `bundle exec whenever` ([official site for whenever](https://github.com/javan/whenever))
5. Run `rake initial_setup`

By default, the Gemfile specifies the 'thin' gem to use for a server. You can deploy this app with Phusion Passenger, Puma, or anything else (please don't use WEBrick), but I use thin for development.

## Saltstorm is a WIP
Saltstorm is unstable and has no version number. Stuff will constantly break.

## License Info
AGPL3.

## Saltstorm Uses Cool Technologies
I built Saltstorm with Sinatra and Sequel. The Rakefile uses Highline for user input. whenever makes the cron job for sending e-mails. mail sends e-mails. Tests use rspec, rack-test, and factory\_girl.

The front-end uses jQuery (every web front-end uses it), AngularJS, and ~~Twitter~~ Bootstrap 3.0. Javascript & CSS are pulled from CDNs provided by Google and [Bootstrap CDN](http://bootstrapcdn.com).

