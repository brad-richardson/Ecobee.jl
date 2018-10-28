module Ecobee

export generate_pin, fetch_oauth_tokens, refresh_tokens,
    fetch_thermostat_ids, fetch_data,
    column_title, DEFAULT_COLUMNS, ALL_COLUMNS

using HTTP
using JSON
using Dates

include("auth.jl")
include("columns.jl")

function generate_pin(api_key, scope=WRITE_SCOPE)
    query = "response_type=ecobeePin&client_id=$api_key&scope=$scope"
    r = make_request("/authorize", query)
    return (pin=r["ecobeePin"], auth_code=r["code"], expires=r["expires_in"])
end

function fetch_oauth_tokens(api_key, auth_code)
    query = "grant_type=ecobeePin&code=$auth_code&client_id=$api_key"
    r = make_request("/token", query, method="POST")
    return (refresh_token=r["refresh_token"], access_token=r["access_token"], expires=r["expires_in"])
end

function refresh_tokens(refresh_token, api_key)
    query = "grant_type=refresh_token&code=$refresh_token&client_id=$api_key"
    r = make_request("/token", query, method="POST")
    return (refresh_token=r["refresh_token"], access_token=r["access_token"])
end

function fetch_thermostat_ids(access_token)
    body = JSON.json(Dict(
        "selection" => Dict(
            "selectionType" => "registered",
            "selectionMatch" => ""
        )
    ))
    r = make_request("/1/thermostat", "format=json&body=$body", access_token)
    return map(t -> t["identifier"], r["thermostatList"])
end

function fetch_data(access_token, thermostat_ids; columns=DEFAULT_COLUMNS, days_ago_start=1, days_ago_end=0)
    days_ago_date = d -> string(Dates.today() - Dates.Day(d))
    body = JSON.json(Dict(
        "startDate" => days_ago_date(days_ago_start),
        "endDate" => days_ago_date(days_ago_end),
        "columns" => join(columns, ","),
        "selection" => Dict(
            "selectionType" => "thermostats",
            "selectionMatch" => join(thermostat_ids, ","),
            "includeElectricity" => true
        )
    ))
    r = make_request("/1/runtimeReport", "format=json&body=$body", access_token)
    data = Dict()
    for report in r["reportList"]
        thermostat_id = report["thermostatIdentifier"]
        data[thermostat_id] = report["rowList"]
    end
    return data
end

function column_title(column)
    return COLUMN_TITLE_LOOKUP[column]
end

function make_request(path, query, access_token=nothing; method="GET")
    url = "https://api.ecobee.com$path"
    headers = access_token != nothing ? Dict("Authorization" => "Bearer $access_token") : []
    r = HTTP.request(method, url, headers; query=query)
    return JSON.parse(String(r.body))
end


end
