#!/usr/bin/env ruby

require './harvest.rb'
require 'io/console'
require 'json'
require 'date'
require 'erb'
require 'ostruct'


# read email/password
puts "Enter your harvest email:"
email = STDIN.readline.strip
puts "Password:"
password = ''
STDIN.noecho do
  password = STDIN.readline.strip
end

# initialize API
harvest = Harvest.new(email, password)

# we are interested in stuff since:
d = DateTime.now
d -= d.wday + 7 # go to sunday a week ago
datestr = d.strftime('%Y-%m-%d+%H%%3A%M')


# grab list of projects updated in the last week.
url = '/projects?updated_since=' + datestr
projects = JSON.parse(harvest.request(url, :get).body).map do |project_doc|
  {
    id: project_doc['project']['id'],
    name: project_doc['project']['name'],
    client_id: project_doc['project']['client_id']
  }
end

# for each project, grab the client name
projects.each do |project|
  url = '/clients/' + project[:client_id].to_s
  client_doc = JSON.parse(harvest.request(url, :get).body)
  project[:client_name] = client_doc['client']['name']
end

# now grab the users
url = '/people'
users = JSON.parse(harvest.request(url, :get).body).map do |user_doc|
  {
    id: user_doc['user']['id'],
    name: user_doc['user']['first_name'] + ' ' + user_doc['user']['last_name']
  }
end

# zero out all user/projects
project_user_hours = {}
projects.each do |project|
  users.each do |user|
    project_user_hours[project[:id]] ||= {}
    project_user_hours[project[:id]][user[:id]] = 0
  end
end

# now grab the timesheet for each user
users.each do |user|
  from = d.strftime('%Y%m%d')
  to = (d + 7).strftime('%Y%m%d')
  url = '/people/' + user[:id].to_s + '/entries?from=' + from + '&to=' + to
  JSON.parse(harvest.request(url, :get).body).each do |entry_doc|
    project_id = entry_doc['day_entry']['project_id']
    project_user_hours[project_id][user[:id]] += entry_doc['day_entry']['hours']
  end
end

# filter out users that have done no hours
users = users.select do |user|
  project_user_hours.values.map { |hs| hs[user[:id]] }.reduce(:+) > 0
end

# add a total to each project
projects.each do |project|
  project[:total] = project_user_hours[project[:id]].values.reduce(:+)
end

# we have our data! Print:

# potentially slightly dodgy approach
def erb(template, vars)
  ERB.new(template).result(OpenStruct.new(vars).instance_eval { binding })
end

locals = {
  users: users,
  projects: projects,
  project_user_hours: project_user_hours
}
template = File.open('email.erb').read
puts erb(template, locals)