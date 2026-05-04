require 'rack/test'
require 'json'
require_relative '../../../app/api'

# External JSON API — authenticated via secret key in the path, not session cookies.
module MemberTracker
  RSpec.describe 'External API Routes (/api)', :db do
    include Rack::Test::Methods

    def app
      MemberTracker::API.new
    end

    # ── Renewal Find ──────────────────────────────────────────────────────────

    describe 'GET /api/mbr_renewal/find/:secret' do
      it 'returns a rejection payload for an invalid secret' do
        get '/api/mbr_renewal/find/wrong_secret'
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)).to eq('sorry')
      end

      it 'returns renewal check results for a valid secret' do
        ENV['MBRRENEW_SECRET'] = 'test_renew_secret'
        get '/api/mbr_renewal/find/test_renew_secret'
        expect(last_response.status).to eq(200)
        # seeded mbr_renew_check log has ts=today so getRenewRangeStart returns "wait"
        expect(JSON.parse(last_response.body)).to eq('already checked today')
      ensure
        ENV.delete('MBRRENEW_SECRET')
      end
    end

    # ── Renewal 2nd Notice ────────────────────────────────────────────────────

    describe 'GET /api/mbr_renewal/2nd_notice/:secret' do
      it 'returns a rejection payload for an invalid secret' do
        get '/api/mbr_renewal/2nd_notice/wrong_secret'
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)).to eq('sorry')
      end

      it 'returns members due a second renewal notice for a valid secret' do
        ENV['MBRRENEW_SECRET'] = 'test_renew_secret'
        get '/api/mbr_renewal/2nd_notice/test_renew_secret'
        expect(last_response.status).to eq(200)
        # no active renewals in test DB — get2ndNotice returns ["empty"]
        parsed = JSON.parse(last_response.body)
        expect(parsed).to eq(['empty'])
      ensure
        ENV.delete('MBRRENEW_SECRET')
      end
    end

    # ── Member Sync ───────────────────────────────────────────────────────────

    describe 'GET /api/mbr_sync/SP2ejIsG/:secret' do
      it 'returns a rejection payload for an invalid secret' do
        get '/api/mbr_sync/SP2ejIsG/wrong_secret'
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)).to eq('sorry')
      end

      it 'returns member sync payload as JSON for a valid secret' do
        ENV['MBRSYNC_SECRET'] = 'test_sync_secret'
        get '/api/mbr_sync/SP2ejIsG/test_sync_secret'
        expect(last_response.status).to eq(200)
        parsed = JSON.parse(last_response.body)
        expect(parsed).to be_a(Hash)
      ensure
        ENV.delete('MBRSYNC_SECRET')
      end
    end
  end
end
