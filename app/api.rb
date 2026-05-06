require 'sinatra/base'
require 'json'
require 'bcrypt'
require_relative 'member'
require_relative 'unit'
require_relative 'unitType'
require_relative 'auth_user'
require_relative 'role'
require_relative 'action'
require_relative 'log'
require_relative 'payment'
require_relative 'paymentType'
require_relative 'paymentMethod'
require_relative 'auditLog'
require_relative 'event'
require_relative 'eventType'
require_relative 'referType'
require_relative 'mbrRenewal'
require_relative 'renewalEventType'
require_relative 'memberAction'
require_relative 'memberActionType'
require_relative 'routes/auth_routes'
require_relative 'routes/event_routes'
require_relative 'routes/log_routes'
require_relative 'routes/unit_routes'
require_relative 'routes/renewal_routes'
require_relative 'routes/payment_routes'
require_relative 'routes/followup_routes'
require_relative 'routes/admin_routes'
require_relative 'routes/member_routes'
require_relative 'services/payment_service'

module MemberTracker
  PER_PAGE = 25
  #using modular (cf classical) approach (see https://www.toptal.com/ruby/api-with-sinatra-and-sequel-ruby-tutorial)
  Paid_up = Struct.new(:active, :condition)
  class API < Sinatra::Base
    def initialize(member: nil, auth_user: nil)
      @payment = Payment.new
      @member = member || Member.new
      @auth_user = auth_user || AuthUser.new
      @role = Role.new
      @log = Log.new
      @action = Action.new
      @event = Event.new
      super()
    end
    enable :sessions
    enable :logging
    set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(32) }
    helpers do
      def log_error(e, context = nil)
        msg = context ? "[#{context}] #{e.class}: #{e.message}" : "#{e.class}: #{e.message}"
        logger.error msg
        logger.error e.backtrace.first(5).join("\n") if e.backtrace
      end

      def pagination_links(page, total_pages, base_path, extra_params = {})
        return '' if total_pages <= 1
        btn = 'px-3 py-1 border border-gray-300 rounded text-sm'
        build_url = ->(p) {
          parts = extra_params.map { |k, v| "#{k}=#{Rack::Utils.escape(v.to_s)}" }
          parts << "page=#{p}"
          "#{base_path}?#{parts.join('&')}"
        }
        prev_link = page > 1 ?
          "<a href=\"#{build_url.(page - 1)}\" class=\"#{btn} hover:bg-gray-100 text-blue-600\">&larr; Prev</a>" :
          "<span class=\"#{btn} text-gray-300 cursor-not-allowed\">&larr; Prev</span>"
        next_link = page < total_pages ?
          "<a href=\"#{build_url.(page + 1)}\" class=\"#{btn} hover:bg-gray-100 text-blue-600\">Next &rarr;</a>" :
          "<span class=\"#{btn} text-gray-300 cursor-not-allowed\">Next &rarr;</span>"
        "<div class=\"flex items-center gap-3 mt-4\">" \
          "#{prev_link}" \
          "<span class=\"text-sm text-gray-600\">Page #{page} of #{total_pages}</span>" \
          "#{next_link}" \
        "</div>"
      end
    end
    if ENV["RACK_ENV"] == 'production'
      before do # need to comment this for RSpec
        next if ['/login', "/api/mbr_sync/SP2ejIsG/#{ENV['MBRSYNC_SECRET']}"].include?(request.path_info)
        if session[:auth_user_id].nil?
          redirect '/login'
          #elsif session[:auth_user_id] == 'reset'
          #redirect "/reset_password/#{XXX}"
        end
      end
    else
      before do
        #give dev user credentials NOTE there must be an auth_user in the auth_users table with id == 22
        session[:auth_user_id] = 22
        session[:auth_user_roles] =['auth_u', 'mbr_mgr', 'read_only']
      end
    end
    before '/a/*' do
      authorize!("auth_u")
    end
    before '/m/*' do
      #need to make exception for read_only editing their own profile
      ro_test_route = params['splat'][0].split('/')
      ro_action = ro_test_route.shift
      mbr_id = AuthUser[session[:auth_user_id]].mbr_id.to_s
      #test for matching id
      allow = false
      if ro_action == 'save'
        if params[:id] == mbr_id
          allow = true
        end
      elsif ro_action == 'edit'
        if ro_test_route.pop == mbr_id
          allow = true
        end
      elsif ro_action == 'auth_user' && ro_test_route.first == 'change_password'
        allow = true
      end
      unless allow == true
        authorize!("mbr_mgr")
      end
    end
    before '/r/*' do
      authorize!("read_only")
    end
    def authorize!(role)
      if !session[:auth_user_roles].include?(role)
        session[:msg] = "Sorry, you don't have permission"
        redirect '/home'
      end
    end
    register AuthRoutes
    register EventRoutes
    register LogRoutes
    register UnitRoutes
    register RenewalRoutes
    register PaymentRoutes
    register FollowupRoutes
    register AdminRoutes
    register MemberRoutes
    #################### start from test environment ##########
    get '/members/:name', :provides => 'json' do
      JSON.generate(@member.members_with_lastname(params[:name]))
    end
    get '/members/:name', :provides => 'html' do
      output = ''
      @member.members_with_lastname(params[:name]).each  {|mbr|
        output << "<p>#{mbr}</p>\n"
      }
      output
    end
    post '/members' do
      request.body.rewind
      member_data = JSON.parse(request.body.read)
      result = @member.record(member_data)
      if result.success?
        JSON.generate('member_id' => result.member_id)
      else
        status 422
        JSON.generate('error' => result.message)
      end
    end
    #################### end from test environment ##########
  end
end
