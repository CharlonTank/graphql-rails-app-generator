# graphql-rails-app-generator
Generate your GraphQL rails app with one CLI command - And choose your front!

# Uses
If you don't precise the front you want to generate, the generator will generate the back only.
We only support Elm right now but more to come!

# Troubleshoot
If you get a problem with the generator and get "Address already in use - bind(2) (Errno::EADDRINUSE)"
run the following command to kill the corresponding server:
`lsof -i :3123 -sTCP:LISTEN | awk 'NR > 1 {print $2}' | xargs kill -9 &> /dev/null`
# Contributing
Feel free to contribute and add your lovely front! :)
