require 'rubygems'
require 'zip/zip'
require 'mp3info'

archive = ARGV[0]
if !archive 
    archive = File.join(Dir.pwd, 'media', '9', 'Thought_and_Memory.zip')
end
puts archive

Zip::ZipFile.open(archive) do |zip_file|
    zip_file.each do |entry|
        next if File.extname(entry.name) != ".mp3"

        zip_file.get_input_stream(entry) do |io|
            StringIO.open(io.read) do |sio|
                Mp3Info.open(sio) do |mp3|
                    length = mp3.length
                    lmin = (length / 60.0).to_i
                    lsec = length.to_i % 60
                    if lsec < 10
                        lsec = '0' << lsec.to_s
                    else
                        lsec = lsec.to_s
                    end
                    fmt_length = ' (' << lmin.to_s << ':' << lsec << ')'
                    puts "#{mp3.tag.tracknum}. #{mp3.tag.artist} - #{mp3.tag.album} - #{mp3.tag.title} #{fmt_length}"
                end
            end
        end
    end
end

# http://sox.sourceforge.net/
