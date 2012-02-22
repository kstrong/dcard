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

    has n, :downloads, :through => Resource
end

class Download
    include DataMapper::Resource

    property :id,      Serial
    property :title,   String
    property :path,    String
    property :format,  String
    property :storage, String

    has n, :codes, :through => Resource
    has n, :download_logs
end

class DownloadLog
    include DataMapper::Resource

    belongs_to :download, :key => true

    property :code,       String
    property :ip_address, String
    property :email,      String
    property :format,     String
    property :timestamp,  DateTime
end

DataMapper.finalize

DataMapper.auto_upgrade!

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
        session[:code] = params[:code]
        if params[:email] 
            session[:email] = params[:email]
        end
        redirect to("/download/#{params['code']}")
    else
        flash[:error] = "This code is invalid."
        redirect to('/download')
    end
end

get '/download/:code' do
    redirect '/download' unless codes.include? params[:code]
    @downloads = Code.first(:code => params[:code]).downloads
    erb :download
end

get '/download/:code/:download_id' do
    if ! codes.include? params[:code] 
        halt 404
    end

    download = Download.first(:id => params[:download_id], 
                              :codes => { :code => params[:code] })
    
    puts download.inspect
    if ! download
        halt 403
    end

    if download.storage == "local"
        DownloadLog.create(
          :code => params[:code],
          :download => download,
          :ip_address => request.ip,
          :email => session[:email],
          :format => download.format,
          :timestamp => Time.now
        )
        send_file File.join(Dir.pwd, download.path)
    else
        halt 501
    end
end

get '/manage' do
    erb :admin
end

not_found do
    halt 404, 'not found'
end
