require 'rack/test'
require 'json'
require_relative '../../../app/api'

module MemberTracker
  RSpec.describe 'Public Routes', :db do
    include Rack::Test::Methods

    def app
      MemberTracker::API.new
    end

    # Dev/test before-filter hard-codes session[:auth_user_id] = 22 on every
    # request, so we never test production-only redirect-to-login behavior here.
    # POST /login and POST /logout are tested against their actual redirect logic.

    describe 'GET /' do
      it 'returns 200' do
        get '/'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /login' do
      it 'renders the login form' do
        get '/login'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('action="/login"')
      end
    end

    describe 'POST /login' do
      # Credentials matching the dev-admin seeded in spec/support/db.rb.
      let(:valid_creds) { { 'email' => 'dev_admin@example.com', 'password' => 'Dev@dmin1' } }

      it 'redirects to /home with valid credentials' do
        post '/login', valid_creds
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/home')
      end

      it 'redirects to /login on bad password' do
        post '/login', valid_creds.merge('password' => 'wrongpass')
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/login')
      end

      it 'redirects to /login on unknown email' do
        post '/login', 'email' => 'nobody@example.com', 'password' => 'anything'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/login')
      end

      it 'redirects to /login when a required field is missing' do
        post '/login', 'email' => 'dev_admin@example.com'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/login')
      end
    end

    describe 'POST /logout' do
      it 'clears the session and redirects to /login' do
        post '/logout'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/login')
      end
    end

    describe 'GET /home' do
      # Requires a seeded mbr_renew_check log (done in spec/support/db.rb before(:suite))
      # so the route doesn't crash on nil[:ts] when no renewal check has run yet.
      it 'renders the home page' do
        get '/home'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('PARC Home')
      end
    end

    describe 'GET /reset_password/:id' do
      it 'renders the reset-password form for a valid member id' do
        member = create_member(fname: 'Test', lname: 'Reset')
        get "/reset_password/#{member.id}"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('/reset_password')
      end

      it 'returns 404 or redirects for an unknown member id' do
        get '/reset_password/999999'
        expect(last_response.status).to eq(302)
      end
    end

    describe 'POST /reset_password' do
      it 'updates the password and redirects to /login' do
        member = create_member
        create_auth_user(member: member, password: 'OldP@ss1')
        post '/reset_password', 'password' => 'NewP@ss1', 'mbr_id' => member.id.to_s
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/login')
      end

      # Password strength and confirmation-match are enforced client-side only (script.js).
      # The route accepts any non-empty password string without server-side validation,
      # so there is no server behaviour to test for these two cases.
    end

    describe 'GET /check/mbrship/status' do
      it 'renders the membership status check form' do
        get '/check/mbrship/status'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('mbrIdentifier')
      end
    end

    describe 'POST /check/mbrship/status' do
      it 'returns active status for a current member' do
        create_member(callsign: 'W9ACT', mbrship_renewal_date: Date.today)
        post '/check/mbrship/status', 'mbrIdentifier' => 'W9ACT'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('active')
      end

      it 'returns expired status for a lapsed member' do
        create_member(callsign: 'W9EXP', mbrship_renewal_date: Date.today - 400)
        post '/check/mbrship/status', 'mbrIdentifier' => 'W9EXP'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('expired')
      end

      it 'returns not-found for an unrecognized callsign or email' do
        post '/check/mbrship/status', 'mbrIdentifier' => 'NOCALL_XYZ'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('not found')
      end
    end
  end
end
