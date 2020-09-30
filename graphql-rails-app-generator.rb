#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'io/console'
require_relative 'src/wait_for_it'
require_relative 'src/utils'

options = {}

# Parsing options
OptionParser.new do |parser|
  parser.on('-n', '--name NAME', 'The name of your project') do |name|
    options[:name] = name
  end
  parser.on('-p', '--path PATH', 'The path of your project') do |path|
    options[:path] = path
    Dir.mkdir options[:path] unless Dir.exist?(options[:path])
  end
  parser.on('--no-pg-uuid', 'Disables PostgreSQL uuid extension') do
    options['--no-pg-uuid'] = true
  end
  parser.on('--no-action-cable-subs', 'Disables ActionCable websocket subscriptions') do
    options['--no-action-cable-subs'] = true
  end
  parser.on('--no-apollo-compatibility', 'Disables Apollo compatibility') do
    options['--no-apollo-compatibility'] = true
  end
  parser.on('--no-users', 'Runs the script with no user migrations') do
    options['--no-users'] = true
  end
  parser.on('-f', '--front FRONT', 'The front of your project') do |front|
    options[:front] = front
  end
  parser.on('--no-front', 'Disables front generation') do
    options[:no_front] = true
  end
end.parse!

clear_console

Dir.chdir options[:path] unless options[:path].blank?

# Name of the project
loop do
  if options[:name].blank?
    puts 'What is the name of your project?'
    options[:name] = gets.chomp
  end
  options[:name] = to_valid_file_name options[:name]
  if File.exist?(options[:name])
    clear_console
    puts "The directory #{options[:name]} already exists"
    puts "in : #{options[:path]}" unless options[:path].blank?
    options[:name] = nil
    next
  end
  puts 'The directory created will be ' + options[:name]
  puts 'Is that what you want? Type Y for yes, N for no, A for abort'
  case yesno
  when 't' then break
  when 'f' then
    clear_console
    puts 'Old name : ' + options[:name]
    options[:name] = nil
  when 'a' then
    puts '...Aborting generation...'
    return
  else raise 'A problem occured, please try launching the script again'
  end
end

clear_console

# Front of the project
if !options[:no_front] && options[:front].blank?
  loop do
    puts 'What is the frontend of your project?'
    puts 'Only "elm" and "ts" are supported now, otherwise type "s" to skip the front generation or "a" to abort'
    case gets.chomp
    when 'elm' then
      options[:front] = 'elm'
      break
    when 'ts', 'react' then
      options[:front] = 'typescript'
      break
    when 's', 'S', 'skip' then
      options[:no_front] = true
      break
    when 'a', 'A', 'abort' then
      puts '...Aborting generation...'
      return
    else
      clear_console
      puts 'Invalid front name.'
    end
  end
end

clear_console

puts options[:front] ? "#{options[:front]} choosen" : 'No front choosen'

# API Generation
show_and_do("Generating #{options[:name]} api ...") do
  Dir.mkdir options[:name]
  Dir.chdir options[:name]
  `rails new #{options[:name]}-api --api --database=postgresql &> /dev/null`
end

show_and_do('Adding graphql, graphql-rails-api and rack-cors to the Gemfile ...') do
  Dir.chdir options[:name] + '-api'
  `bundle add graphql --skip-install &> /dev/null`
  `bundle add graphql-rails-api --skip-install &> /dev/null`
  `bundle add rack-cors &> /dev/null`
end

show_and_do('Creating database ...') do
  if `rails db:create 2>&1`.include?'already exists'
    puts "\nDatabases '#{options[:name]}_api_development' and '#{options[:name]}_api_test' already exist."
    puts 'Do you want to drop and recreate the databases? [y/n/a]'
    puts 'Type Y to drop and recreate the DB, N to skip and continue the app generation, A to abort'
    case yesno
    when 't'
      show_and_do("Dropping and recreating '#{options[:name]}_api_development' and '#{options[:name]}_api_test'") do
        `rails db:drop &> /dev/null`
        `rails db:create &> /dev/null`
      end
    when 'f' then break
    when 'a' then
      puts '...Aborting generation...'
      return
    else raise 'A problem occured, please try launching the script again'
    end
  end
end

concatened_options = (options['--no-pg-uuid'] ? ' --no-pg-uuid' : '') +
                     (options['--no-action-cable-subs'] ? ' --no-action-cable-subs' : '') +
                     (options['--no-apollo-compatibility'] ? ' --no-apollo-compatibility' : '')

show_and_do("Installing graphql-rails-api#{concatened_options} ...") do
  `spring stop &> /dev/null`
  `rails generate graphql_rails_api:install #{concatened_options} &> /dev/null`
end

show_and_do('Installing Webpacker ...') do
  `spring stop &> /dev/null`
  `rails webpacker:install &> /dev/null`
end

show_and_do('Configuring cors (Cross-Origin Resource Sharing) ...') do
  cors_content =
    %(Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: %i[get post options]
  end
end)

  File.open('config/initializers/cors.rb', 'a+') { |f| f.write(cors_content) }
end

# Front generation
if !options[:no_front] && options[:front]
  if options[:front] == 'elm'

    elm_boiler_plate = File.read('../../src/elm/boiler_plate.elm')

    show_and_do('Launch rails server on port 3123 ...') do
      WaitForIt.new('rails s -p 3123', wait_for: 'Listening on tcp')
    end

    show_and_do("Generating #{options[:name]} front in elm ...") do
      Dir.mkdir "../#{options[:name]}-front"
      Dir.chdir "../#{options[:name]}-front"
      `printf 'y' | elm init &> /dev/null`
    end

    show_and_do('Installing dillonkearns/elm-graphql ...') do
      `printf 'y' | elm install dillonkearns/elm-graphql &> /dev/null`
      `printf 'y' | elm install elm/json &> /dev/null`
    end

    show_and_do('Installing elm-athlete/athlete ...') do
      `printf 'y' | elm install elm-athlete/athlete &> /dev/null`
      `printf 'y' | elm install elm/time &> /dev/null`
      `printf 'y' | elm install elm/url &> /dev/null`
    end

    camelname = camelcase options[:name]

    show_and_do('Configuring package.json ...') do
      elm_package_content =
        %({
      "name": "#{options[:name]}",
      "version": "1.0.0",
      "scripts": {
        "api": "./node_modules/.bin/elm-graphql http://localhost:3000/graphql --base #{camelname}",
        "rails-graphql-api": "./node_modules/.bin/elm-graphql http://localhost:3123/graphql --base #{camelname}",
        "live": "./node_modules/.bin/elm-live src/Main.elm -u --open",
        "lived": "./node_modules/.bin/elm-live src/Main.elm -u --open -- --debug"
      }
    })

      File.open('package.json', 'w') { |f| f.write(elm_package_content) }
    end

    show_and_do('Installing dillonkearns/elm-graphql CLI ...') do
      `npm install --save-dev @dillonkearns/elm-graphql &> /dev/null`
    end

    show_and_do('Installing elm-live CLI ...') do
      `npm install --save-dev elm-live@next &> /dev/null`
    end

    show_and_do('Generating elm with dillonkearns/elm-graphql ...') do
      `npm run rails-graphql-api &> /dev/null`
    end

    show_and_do('Copying boiler_plate.elm ...') do
      File.open('src/Main.elm', 'w') { |f| f.write(elm_boiler_plate) }
    end

    show_and_do('Stopping rails server on port 3123 ...') do
      `lsof -i :3123 -sTCP:LISTEN | awk 'NR > 1 {print $2}' | xargs kill -9 &> /dev/null`
    end
  elsif options[:front] == "typescript"
    
    show_and_do('Launch rails server on port 3123 ...') do
      WaitForIt.new('rails s -p 3123', wait_for: 'Listening on tcp')
    end

    show_and_do("Generating #{options[:name]} front in react with typescript ...") do
      Dir.mkdir "../#{options[:name]}-front"
      Dir.chdir "../#{options[:name]}-front"
    end

    show_and_do("Initialize package.json...") do
      `npm init -y &> /dev/null`
    end

    show_and_do("Installing @types/react and @types/react-dom...") do
      `npm install --save-dev @types/react @types/react-dom &> /dev/null`
    end

    show_and_do("Installing awesome-typescript-loader ...") do
      `npm install --save-dev awesome-typescript-loader &> /dev/null`
    end

    show_and_do("Installing css-loader ...") do
      `npm install --save-dev css-loader &> /dev/null`
    end

    show_and_do("Installing html-webpack-plugin ...") do
      `npm install --save-dev html-webpack-plugin &> /dev/null`
    end

    show_and_do("Installing mini-css-extract-plugin ...") do
      `npm install --save-dev mini-css-extract-plugin &> /dev/null`
    end

    show_and_do("Installing source-map-loader ...") do
      `npm install --save-dev source-map-loader &> /dev/null`
    end

    show_and_do("Installing typescript ...") do
      `npm install --save-dev typescript &> /dev/null`
    end

    show_and_do("Installing webpack, webpack-cli and webpack-dev-server ...") do
      `npm install --save-dev webpack webpack-cli webpack-dev-server &> /dev/null`
    end

    show_and_do("Installing react and react-dom ...") do
      `npm install react react-dom &> /dev/null`
    end

    show_and_do("Preparing project architecture ...") do
        `touch webpack.config.js &> /dev/null`
        `touch tsconfig.json &> /dev/null`
        `mkdir src &> /dev/null`
        `mkdir src/components &> /dev/null`
        `touch src/components/index.html &> /dev/null`
        `touch src/components/App.tsx &> /dev/null`
        `touch src/index.tsx &> /dev/null`
        `mkdir src/styles &> /dev/null`
        `touch src/styles/app.css &> /dev/null`
    end

    show_and_do('Configuring tsconfig content ...') do
      tsconfig_content = 
        %({
  "compilerOptions": {
    "jsx": "react",
    "module": "commonjs",
    "noImplicitAny": true,
    "outDir": "./build/",
    "preserveConstEnums": true,
    "removeComments": true,
    "sourceMap": true,
    "target": "es5"
  },
    "include": [
      "src/components/index.tsx"
    ]
})

        File.open('tsconfig.json', 'w') { |f| f.write(tsconfig_content) }
    end

    show_and_do('Configuring App.tsx content ...') do
      app_tsx_content = 
        %(import * as React from "react";
export interface HelloWorldProps {
  userName: string;
  lang: string;
}
export const App = (props: HelloWorldProps) => (
  <h1>
    Hi {props.userName} ! Welcome to {props.lang} !
  </h1>
);
        )

        File.open('./src/components/App.tsx', 'w') { |f| f.write(app_tsx_content) }
    end

    show_and_do('Configuring index.html content ...') do
      index_html_content = 
        %(<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>React-Webpack Setup</title>
</head>

<body>
    <div id="app"></div>
</body>

</html>
        )

        File.open('./src/components/index.html', 'w') { |f| f.write(index_html_content) }
    end

    show_and_do('Configuring index.tsx content ...') do
      index_tsx_content = 
        %(import * as React from "react";
import * as ReactDOM from "react-dom";
import { App } from "./components/App";

ReactDOM.render(
  <App userName="folks" lang="TypeScript" />,
  document.getElementById("app")
);          
        )

        File.open('./src/index.tsx', 'w') { |f| f.write(index_tsx_content) }
    end

    show_and_do('Configuring package.json content ...') do
      file = IO.read("package.json")
      file = file.gsub("\"test\": \"echo \\\"Error: no test specified\\\" && exit 1\"", "\"start\": \"webpack-dev-server --open\",\n    \"build\": \"webpack\",\n    \"generate\": \"graphql-codegen\"")
      File.write("package.json", file)
    end

    show_and_do('Configuring webpack content ...') do
      webpack_config_content =
        %(const path = require("path");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const MiniCssExtractPlugin = require("mini-css-extract-plugin");
module.exports = {
  entry: "./src/index.tsx",
  target: "web",
  mode: "development",
  output: {
    path: path.resolve(__dirname, "build"),
    filename: "bundle.js",
  },
  resolve: {
    extensions: [".js", ".jsx", ".json", ".ts", ".tsx"],
  },
  module: {
    rules: [
      {
        test: /\.(ts|tsx)$/,
        loader: "awesome-typescript-loader",
      },
      {
        enforce: "pre",
        test: /\.js$/,
        loader: "source-map-loader",
      },
      {
        test: /\.css$/,
        loader: "css-loader",
      },
    ],
  },
  plugins: [
    new HtmlWebpackPlugin({
      template: path.resolve(__dirname, "src", "components", "index.html"),
    }),
    new MiniCssExtractPlugin({
      filename: "./src/styles/app.css",
    }),
  ],
};)

      File.open('webpack.config.js', 'w') { |f| f.write(webpack_config_content) }
    end

    show_and_do('Installing graphql ...') do
      `npm install graphql &> /dev/null`
    end

    show_and_do('Installing @graphql-codegen/cli ...') do
      `npm install --save-dev @graphql-codegen/cli`
    end

    show_and_do('Installing @graphql-codegen/typescript ...') do
      `npm install --save-dev @graphql-codegen/typescript`
    end

    show_and_do('Configuring codegen.yml content ...') do
      `touch codegen.yml &> /dev/null`
      codegen_content = %(schema: http://localhost:3123/graphql
generates:
  ./src/types.d.ts:
    plugins:
      - typescript)

      File.open("codegen.yml", "w") { |f| f.write(codegen_content) }
    end

    show_and_do('Run graphql_codegen ...') do
      `npm run generate`
    end

    show_and_do('Stopping rails server on port 3123 ...') do
      `lsof -i :3123 -sTCP:LISTEN | awk 'NR > 1 {print $2}' | xargs kill -9 &> /dev/null`
    end
  end
end

puts "\nSuccessful installation!".green

if options[:no_front]
  puts 'You can now, run your rails server:'.green
  puts '  rails s'.yellow + " in #{options[:name]}-api".green
elsif options[:front] == 'elm'
  puts 'You can now, run your rails server and front server:'.green
  puts '  rails s'.yellow + " in #{options[:name]}-api".green
  puts '  npm run live'.yellow + " in #{options[:name]}-front".green
elsif options[:front] == 'typescript'
  puts 'You can now, run your rails server and front server:'.green
  puts '  rails s'.yellow + " in #{options[:name]}-api".green
  puts '  npm start'.yellow + " in #{options[:name]}-front".green
end
