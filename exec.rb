require 'rest-client'
require 'json'
require 'yaml'
require "base64"
require 'securerandom'
require 'colorize'
require 'faker'
require 'jsonpath'

testedOperations = []

secret = ENV['PURECLOUD_SECRET']
id = ENV['PURECLOUD_CLIENT_ID']

basic = Base64.strict_encode64("#{id}:#{secret}")

tokenData = JSON.parse RestClient.post('https://login.mypurecloud.com/oauth/token',
{:grant_type => 'client_credentials'},
:Authorization => "Basic " + basic,
'content-type'=> 'application/x-www-form-urlencoded',
:accept => :json)


@authHeader = tokenData["token_type"] + ' ' + tokenData["access_token"]

uri = URI("https://api.inindca.com/api/v2/docs/swagger")
@swagger = JSON.parse Net::HTTP.get(uri)


def get_operation_definition(id)
    @swagger["paths"].each do |path, pathOperations|
        pathOperations.each do |httpMethod, operationDefinition|
            operationDefinition["url"] = path
            operationDefinition["httpMethod"] = httpMethod

            return operationDefinition if operationDefinition["operationId"] == id
        end
    end

    puts "#{id} NOT FOUND".red
end

def get_value(name, definition)
    type = definition["type"]

    if(name == "email")
        return SecureRandom.hex + "@testrun.fake"
    elsif (type == "string")
        return SecureRandom.hex
    elsif (type == "array")
        if(definition["items"]["format"] == "uri")
            return [Faker::Internet.url]
        else
            puts "TYPE #{definition["items"]["type"]} NOT HANDLED".red
        end
    else
        puts "TYPE #{type} NOT HANDLED".red
    end
end

def get_body(modelName)
    modelName.gsub!(/#\/definitions\//,'');
    model = @swagger["definitions"][modelName]

    puts "MODEL NOT FOUND ".red if model == nil

    body ={}

    model["properties"].each do |name, definition|
        if model["required"] != nil && model["required"].include?(name)
            body[name] = get_value name, definition
        end
    end

    body
end


def make_request(url, httpMethod, body)
    #url = "https://api.mypurecloud.com#{url}"
    url = "https://api-mypurecloud-com-6utcaoovepde.runscope.net#{url}"

    if(body == nil)
        RestClient::Request.execute(method: httpMethod.to_sym, url: url,
        headers: {Authorization: @authHeader, :accept => :json,  :content_type => :json})
    else
        RestClient::Request.execute(method: httpMethod.to_sym, url: url,
        payload: body.to_json, headers: {Authorization: @authHeader, :accept => :json,  :content_type => :json})
    end

end

#testSuite = ["authorization.yml"]
testSuite = ["oauth_clients.yml", "presence.yml", "authorization.yml"]

testSuite.each do |testrun|

    variables = {}

    run = YAML.load_file(testrun)

    run.each do |step|
        body = nil
        puts "Calling " + step["operationId"]

        operationDef = get_operation_definition step["operationId"]

        url = operationDef["url"].dup

        operationDef["parameters"].each do |param|
            if param["in"] == "body"
                body = get_body param["schema"]["$ref"]
            end
        end

        if step["params"] != nil
            step["params"].each do |param, value|
                val = value

                if value[0] == '$'
                    val = variables[value.sub(/\$/, '')]
                end

                if(url.include? "{#{param}}")
                    url.gsub! /\{#{param}\}/,val
                else
                    body[param] = val
                end
            end
        end

        response = nil
        begin
            response = make_request(url, operationDef["httpMethod"], body)
        rescue => e
          response = e.response
        end

        if step["response"]
            if(step["response"]["status"])
                if(step["response"]["status"] != response.code)
                    puts "INVALID STATUS RETURNED".red
                end
            end

            if(step["response"]["variables"])
                responseHash = JSON.parse response
                step["response"]["variables"].each do |varName, varParam|
                    jpath = JsonPath.new("$#{varParam}")

                    variables[varName] = jpath.on(response)[0]
                    #puts variables
                end
            end

        end

        if !testedOperations.include? step["operationId"]
            testedOperations.push step["operationId"]
        end
    end
    puts "#{variables}"
    puts "Completed #{testrun}".green
end

methodCount = 0;
@swagger["paths"].each do |path, pathData|
    pathData.each do |method, data|
        methodCount = methodCount + 1
    end

end

puts "TEST COMPLETE"
puts "Operations Tested: #{testedOperations.count} "
puts "Total Operations: #{methodCount} "
pct = testedOperations.count/ methodCount.to_f
puts "Test Coverage: #{pct * 100}"
