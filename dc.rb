require 'rubygems'
require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/flash'
require 'data_mapper'
require 'json'
require 'aws/s3'
require File.join(File.dirname(__FILE__), 'config')

enable :sessions

require File.join(File.dirname(__FILE__), 'models')

AWS::S3::Base.establish_connection!(
    :access_key_id     => settings.aws_access,
    :secret_access_key => settings.aws_secret
)

helpers do
    include Rack::Utils
    alias_method :h, :escape_html

    def download_url_for(download)
        url("download/#{session[:code]}/#{download.id}") 
    end

    def torrent_url_for(download)
        url("download/#{session[:code]}/#{download.id}/torrent") 
    end
end

get '/' do
    redirect '/download'
end

get '/download' do
    erb :access
end

post '/download' do
    if ! params.has_key? 'code' 
        flash[:error] = "Please enter a download code."
        redirect to('/download')
    end

    code = Code.first(:code => params[:code])

    if ! code.nil? && code.downloads.count > 0
        session[:code] = params[:code]
        if params[:email] 
            session[:email] = params[:email]
        end
        redirect to("/download/#{params['code']}")
    else
        flash[:error] = "This code is either expired or invalid."
        redirect to('/download')
    end
end

get '/download/:code' do
    @code = Code.first(:code => params[:code])

    if @code.nil? 
        redirect '/download'
    elsif @code.downloads.count == 0
        flash[:error] = "There are no more downloads available for this code"
        redirect '/download'
    else
        @downloads = @code.downloads
        erb :download
    end
end

get '/download/:code/:download_id/torrent' do
    halt 403 unless session[:code] == params[:code]

    download = Download.first(:id => params[:download_id], 
                              Download.codes.code => params[:code])
    
    if ! download || download.storage != "s3"
        halt 404
    end

    attachment "#{download.title}.torrent"
    AWS::S3::S3Object.torrent_for download.path, settings.bucket
end

get '/download/:code/:download_id' do
    halt 403 unless session[:code] == params[:code]

    download = Download.first(:id => params[:download_id], 
                              Download.codes.code => params[:code])
    
    if ! download
        halt 404
    end

    DownloadLog.create(
      :code       => params[:code],
      :download   => download,
      :ip_address => request.ip,
      :email      => session[:email],
      :format     => download.format,
      :timestamp  => Time.now
    )

    # decrement count of downloads remaining
    rel = download.code_downloads.first(:code => Code.first(:code => params[:code]))
    rel.count = rel.count - 1
    if rel.count == 0 
        rel.destroy
    else
        rel.save
    end

    if download.storage == "local"
        filepath = File.join(Dir.pwd, download.path)
        send_file filepath,
          :filename => File.basename(filepath),
          :disposition => 'attachment'

    elsif download.storage == "s3"
        redirect AWS::S3::S3Object.url_for download.path, settings.bucket

    else
        halt 501
    end
end

post '/download/new' do
    if ! params.has_key? 'title' or params[:title].length == 0
        flash[:error] = "Title is required"
        return redirect '/manage'
    elsif ! params.has_key? 'download_file'
        flash[:error] = "Please choose a file to upload"
        return redirect '/manage'
    end

    tmpfile = params[:download_file][:tempfile]
    filename = params[:download_file][:filename].gsub(/\s/, '_')

    download = Download.create(
      :title   => params[:title],
      :path    => filename,
      :format  => File.extname(filename),
      :storage => params[:storage]
    )

    if params[:storage] == "local"
        directory = File.join(Dir.pwd, 'media', download.id.to_s)
        Dir::mkdir(directory) unless File.exists?(directory)

        path = File.join(directory, filename)

        File.open(path, "wb") do |f| 
            f.write tmpfile.read
        end

        download.path = File.join('/media', download.id.to_s, filename)

    elsif params[:storage] == "s3"
        s3file = "/#{download.id.to_s}/#{filename}" 

        AWS::S3::S3Object.store s3file, tmpfile.read, settings.bucket

        download.path = s3file
    end

    download.save

    redirect '/manage'
end

delete '/download/:id' do
    download = Download.get(params[:id])

    if download.storage == "local"
        filepath = File.join(Dir.pwd, download.path)
        File.delete filepath

    elsif download.storage == "s3"
        AWS::S3::S3Object.delete download.path, settings.bucket
    end

    CodeDownload.all(:download_id => download.id).destroy

    if download.destroy
        { :status => 'ok' }.to_json
    else
        { :error => download.errors.map{|e| e}.join("\n") }.to_json
    end
end

get '/manage' do
    @codes        = Code.all
    @downloads    = Download.all
    @default_count = 1
    erb :admin
end

# #
# Codes - JSON API
# #

def make_code(downloads, codeword)
    code = Code.new
    if codeword && codeword.length > 0
        code.code = codeword
    else 
        codeword = rand(36**8).to_s(36)

        # sometimes the function generates collisons 
        # so keep regenerating until we get one that isn't used
        attempts = 0
        until Code.first(:code => codeword).nil? || attempts > 10
            codeword = rand(36**8).to_s(36)
            attempts += 1
        end

        code.code = codeword
    end
    
    if code.save
        downloads.each { |dl_id, cnt|
            CodeDownload.create(
              :code_id     => code.id,
              :download_id => dl_id,
              :count       => cnt
            )
        } if downloads

        code
    else
        { :error => code.errors.map{|e| e}.join("\n") }
    end
end

post '/codes' do
    params[:count] = params[:count].to_i
    params[:count] = 1 if params[:count].nil? or params[:count] == 0

    content_type :json

    codes = []

    baseword = params[:codeword] if params.has_key? 'codeword'

    counter = 1
    errors = nil
    params[:count].times do 
        if baseword
            codeword = "#{baseword}#{counter}"
        else 
            codeword = ""
        end 

        result = make_code(params[:downloads], codeword)
        if result.instance_of? Code
            codes << result
        else
            errors = result
            break
        end

        counter += 1
    end

    if errors
        errors.to_json
    else
        { :status => "ok", :codes => codes }.to_json
    end
end

put '/codes/:id' do
    code = Code.get(params[:id])

    if code.nil?
        return { :error => "Code #{params[:id]} not found" }.to_json
    end

    ids_set = []

    if params[:downloads] 
        params[:downloads].each do |dl_id, cnt|
            ids_set << dl_id.to_i
            if rel = CodeDownload.get(code.id, dl_id)
                rel.update(:count => cnt)
            else
                CodeDownload.create(
                  :code_id     => code.id,
                  :download_id => dl_id,
                  :count       => cnt
                )
            end
        end
    end

    # delete relationship for downloads that have been unset
    all_dls = CodeDownload.all(:code_id => code.id)
    all_dls.each do |dl_link| 
        if ! ids_set.include? dl_link.download_id
            dl_link.destroy
        end
    end

    code.to_json
end

not_found do
    halt 404, 'not found'
end
