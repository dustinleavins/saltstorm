# Saltstorm - Fun-Money Betting on the Web

## What is Saltstorm?
Saltstorm is an open-source clone of <a href='http://www.saltybet.com'>Salty Bet</a> built with Ruby.

## Deployment
You must have shell access on your web server and the ability to run Rack web apps. Currently, initial setup is a four-step process:
1. Put the files on your server and run `bundle install`
2. Create your database & set it up (if not using SQLite)
3. Create a config/database.yml (example is provided)
4. Run `rake initial_setup`

## Saltstorm is a WIP
Saltstorm is 'extremely unstable' and has no version number. Stuff will constantly break.

## License Info
AGPL3.

## Saltstorm Uses Cool Technologies
I built Saltstorm with Sinatra and Sequel. The Rakefile uses Highline for user input. Tests use rspec, rack-test, and factory\_girl.

The front-end uses jQuery (every web front-end uses it), AngularJS, and ~~Twitter~~ Bootstrap 3.0. Javascript & CSS are pulled from CDNs provided by Google and <a href='http://bootstrapcdn.com'>Bootstrap CDN</a>.

