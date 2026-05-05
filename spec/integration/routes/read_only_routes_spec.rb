require 'rack/test'
require 'json'
require_relative '../../../app/api'

# Routes under /r/ require at least read_only role (rank 3).
# In dev/test mode api.rb hard-codes session[:auth_user_id] = 22 (auth_u rank 1),
# so all /r/ routes are accessible without additional cookie setup.
module MemberTracker
  RSpec.describe 'Read-Only Routes (/r)', :db do
    include Rack::Test::Methods

    def app
      MemberTracker::API.new
    end

    # ── Member ──────────────────────────────────────────────────────────────

    describe 'GET /r/member/list' do
      it 'renders the member list page' do
        get '/r/member/list'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Members List')
      end

      it 'accepts an optional event id parameter to pre-select event attendance mode' do
        get '/r/member/list/1'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /r/member/show/:id' do
      it 'renders the member detail page for a valid member id' do
        member = create_member(fname: 'Alice', lname: 'Testmember')
        get "/r/member/show/#{member.id}"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Alice')
      end

      it 'redirects to /r/member/list for an unknown member id' do
        get '/r/member/show/0'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/r/member/list')
      end
    end

    describe 'GET /r/member/mbr_survey' do
      it 'renders the JotForm survey tally form' do
        get '/r/member/mbr_survey'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Topics')
      end
    end

    describe 'POST /r/member/mbr_survey' do
      it 'returns survey match results (empty list when no survey responses exist)' do
        post '/r/member/mbr_survey', {}
        expect(last_response.status).to eq(200)
      end

      # Filtered-list test omitted: requires inserting JotForm-formatted survey responses
      # in log notes (domain-specific parsing in Member#get_jf_data); not worth the setup.
    end

    describe 'GET /r/member/mbr_rpt' do
      it 'renders the report date-filter form' do
        get '/r/member/mbr_rpt'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('/r/member/mbr_rpt')
      end
    end

    describe 'POST /r/member/mbr_rpt' do
      it 'renders the membership counts report using today as the cutoff date' do
        post '/r/member/mbr_rpt', 'date' => 'date_today', 'newDate' => ''
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('ARRL')
      end

      it 'renders the report for a custom cutoff date' do
        post '/r/member/mbr_rpt', 'date' => 'date_other', 'newDate' => '01/01/24'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('ARRL')
      end

      it 'redirects with an error message when the custom date is unparseable' do
        post '/r/member/mbr_rpt', 'date' => 'date_other', 'newDate' => 'not-a-date'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/mbr_renewals/show')
      end
    end

    # ── Logs ────────────────────────────────────────────────────────────────

    describe 'GET /r/log/logNote/show/:id' do
      it 'renders the log note detail for a valid log id' do
        action_id = DB[:actions].where(type: 'login').get(:id)
        log_id = DB[:logs].insert(ts: Time.now, action_id: action_id,
                                  notes: "test note\r\nline 2")
        get "/r/log/logNote/show/#{log_id}"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('test note')
      end

      it 'redirects to /home for an unknown log id' do
        get '/r/log/logNote/show/0'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/home')
      end
    end

    # ── Events ──────────────────────────────────────────────────────────────

    describe 'GET /r/event/attendance' do
      it 'renders the attendance query form' do
        get '/r/event/attendance'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Attendance Query')
      end
    end

    describe 'POST /r/event/attendance' do
      it 'redirects back with an error when no event type is selected' do
        post '/r/event/attendance', {}
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/r/event/attendance')
      end

      it 'renders the attendance report page for general meeting events (empty result)' do
        post '/r/event/attendance', 'event_type_id' => '1'
        expect(last_response.status).to eq(200)
      end

      # No server-side error path for unknown event/member in this route — validation
      # is client-side only; the template renders with empty data.
    end

    # ── Data Dump ────────────────────────────────────────────────────────────

    describe 'GET /r/dump/:table' do
      it "renders a CSV-style member dump for table 'mbr'" do
        get '/r/dump/mbr'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('First_Name')
      end

      it 'redirects to /home for an unknown table name' do
        get '/r/dump/unknown_table'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/home')
      end
    end
  end
end
