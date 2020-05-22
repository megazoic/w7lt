require_relative 'app/api'
run MemberTracker::API.new
=begin
use Rack::Session::Cookie,
        :key          => 'rack.session', 
        :httponly     => true,
        :same_site    => :strict,
        :path         => '/',
        :expire_after => 86400,
        :secret       => ENV.fetch('SESSION_SECRET')
=end