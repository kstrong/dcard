require 'sinatra'
require 'sinatra/flash'
require 'data_mapper'
require File.join(File.dirname(__FILE__), 'config')

enable :sessions

DataMapper.setup :default, settings.db

class Code
	include DataMapper::Resource

	property :id,         Serial
	property :code,       String
	property :created_at, DateTime
end

class Download
	include DataMapper::Resource

	property :id,      Serial
	property :title,   String
	property :path,    String
	property :format,  String
	property :storage, String
end

codes = ['secretsauce']

get '/' do
	'welcome'
end

get '/download' do
	erb :access
end

post '/download' do
	if ! params.has_key? 'code' 
		flash[:error] = "Please enter a download code."
		redirect to('/download')
	end

	if codes.include? params[:code] 
		redirect to("/download/#{params['code']}")
	else
		flash[:error] = "This code is invalid."
		redirect to('/download')
	end
end

get '/download/:code' do
	redirect '/download' unless codes.include? params[:code]
	erb :download
end
