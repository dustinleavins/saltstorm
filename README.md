# Saltstorm - Fun-Money Betting on the Web

## What is Saltstorm?
Saltstorm is an open-source fun-money betting web app that is heavily inspired by [Salty Bet](http://www.saltybet.com). 
 
### What Makes Saltstorm Different?
Saltstorm:
* Enables admins to push detailed match data to stats sites
* Allows users to spend fun-money (currently on CoD Prestige-like ranks)
* Has a JSON API for clients and administrators

## Deployment
These deployment instructions assume that you have prior experience with deploying Ruby web applications.

### Requirements
Web server with shell access and Ruby (1.9.3 is used for development). Right now, *this web app only supports SQLite and PostgreSQL*. For production, *you need access to a PostgreSQL server*.

### Deployment Instructions
1. Pull this repo and  run `bundle install`
2. Create and setup your database of choice (don't create tables)
3. Create a config/database.yml file to provide DB connection details
    1. `cp config/database.yml.example config/database.yml`
4. Create a config/email.yml file for sending emails to users
    1. `cp config/email.yml.example config/email.yml`
5. Run `rake initial_setup` (this creates tables and does other stuff)
6. Tweak config/site.yml to your liking
    1. *Change the domain* (`domain` setting) to the domain you are deploying Saltstorm to
    2. Change the `main_video_html` setting use 'embed' code for your stream
    3. Please change the name (`site_name`) and description (`site_description`)
7. Setup important cron jobs using `bundle exec whenever` ([official site for whenever](https://github.com/javan/whenever))

The Gemfile includes the 'thin' gem. But you can probably deploy it using anything (please don't use WEBrick).

## Saltstorm is a WIP
Saltstorm is unstable and has no version number. I hope that nothing breaks, but it could!

## License Info
AGPL3.

## Saltstorm Uses Cool Technologies
I built Saltstorm with Sinatra (with sinatra-flash) and Sequel. The Rakefile uses Highline for user input. whenever makes the cron job for sending e-mails. mail sends e-mails. RestClient POSTs data to web users. 

The front-end uses jQuery, AngularJS, and  Bootstrap 3.0. Javascript & CSS are pulled from CDNs provided by Google and [Bootstrap CDN](http://bootstrapcdn.com).

Tests use rspec, rack-test, factory\_girl, and simplecov.

