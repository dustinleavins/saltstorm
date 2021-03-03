# Saltstorm - Fun-Money Betting on the Web

## What is Saltstorm?
Saltstorm is an open-source fun-money betting web app that is heavily inspired by [Salty Bet](http://www.saltybet.com). 
 
### What Makes Saltstorm Different?
Saltstorm:
* Enables admins to push detailed match data to stats sites
* Allows users to spend fun-money (currently on CoD Prestige-like ranks)
* Has a JSON API for clients and administrators ([Example Ruby Script](https://gist.github.com/dustinleavins/6815346))

## Deployment
These deployment instructions assume that you have prior experience with deploying Ruby web applications.

### Requirements
Web server with shell access, Node.js 14.16.x, and Ruby 3.0.0. Right now, *this web app only supports SQLite and PostgreSQL*.

### Deployment Instructions
1. Pull this repo and  run `bundle install`
2. Run `npm install`
3. Create and setup your database of choice (don't create tables)
4. Create a config/database.yml file to provide DB connection details
    1. `cp config/database.yml.example config/database.yml`
5. Create a config/email.yml file for sending emails to users
    1. `cp config/email.yml.example config/email.yml`
6. Run `rake initial_setup RACK_ENV='production'` (this creates tables and does other stuff)
7. Tweak config/site.yml to your liking
    1. *Change the site url* (`site_url` setting) to the URL that others will access Saltstorm from
    2. Change the `main_video_html` setting use 'embed' code for your stream
    3. You can also change the name (`site_name`) and description (`site_description`)
8. Setup important cron jobs using `bundle exec whenever` ([official site for whenever](https://github.com/javan/whenever))
9. Run `npx webpack --mode=production` to build the client-side site
10. Run `bundle exec puma` to start the site.

## Saltstorm is a WIP
Saltstorm is unstable and has no version number. Things could break.

## License Info
AGPL3.

## Saltstorm Uses Cool Technologies
Saltstorm's API uses Sinatra (with sinatra-flash) and Sequel. The Rakefile uses Highline for user input. whenever makes the cron job for sending e-mails. mail sends e-mails. RestClient POSTs data to web users. 

The front-end uses Webpack to package a application AngularJS and  Bootstrap 3.0.

Tests use rspec, rack-test, factory\_bot, and simplecov.
