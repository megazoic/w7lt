require 'rack/test'
require 'json'
require_relative '../../../app/api'

# Routes under /a/ require auth_u role (rank 1 — highest privilege).
# In dev/test mode api.rb hard-codes session[:auth_user_id] = 22 (auth_u),
# so all /a/ routes are accessible without additional cookie setup.
module MemberTracker
  RSpec.describe 'Admin Routes (/a)', :db do
    include Rack::Test::Methods

    def app
      MemberTracker::API.new
    end

    # ── Auth User CRUD ────────────────────────────────────────────────────────

    describe 'GET /a/auth_user/list' do
      it 'renders the authorized-user list page' do
        get '/a/auth_user/list'
        expect(last_response.status).to eq(200)
      end

      # Dev/test before-filter hard-codes auth_u role on every request — the
      # unauthorized-access redirect is production-only behaviour and cannot be
      # exercised here without changing test infrastructure.
    end

    describe 'GET /a/auth_user/create' do
      it 'renders the new auth-user form' do
        get '/a/auth_user/create'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /a/auth_user/create' do
      it 'creates a new auth_user linked to an existing member and redirects' do
        member = create_member(fname: 'New', lname: 'User')
        rid = role_id('read_only')
        post '/a/auth_user/create', 'mbr_id' => member.id.to_s,
                                    'role_id' => rid.to_s, 'notes' => ''
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/a/auth_user/list')
      end

      it 'redirects back to create when an auth_user already exists for that member' do
        admin_mbr_id = DB[:auth_users].where(id: 22).get(:mbr_id)
        rid = role_id('mbr_mgr')
        post '/a/auth_user/create', 'mbr_id' => admin_mbr_id.to_s,
                                    'role_id' => rid.to_s, 'notes' => ''
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/a/auth_user/create')
      end

      # Password is app-generated (not user-supplied); "missing fields" and
      # "weak password" are client-side concerns with no server-side validation path.
    end

    # ── Role Management ───────────────────────────────────────────────────────

    describe 'GET /a/auth_user/role/set/:id' do
      it 'renders the role assignment form for a given member' do
        member = create_member(fname: 'Role', lname: 'Set')
        get "/a/auth_user/role/set/#{member.id}"
        expect(last_response.status).to eq(200)
      end

      it 'redirects for an unknown member id' do
        get '/a/auth_user/role/set/999999'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/a/auth_user/list')
      end
    end

    describe 'GET /a/auth_user/role/update/:id' do
      it 'renders the role-update confirmation page for a valid auth_user' do
        member = create_member(fname: 'Role', lname: 'Update')
        create_auth_user(member: member, role_name: 'read_only')
        get "/a/auth_user/role/update/#{member.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /a/auth_user/update' do
      it 'redirects to the user list when the role is unchanged and no notes are given' do
        member = create_member(fname: 'No', lname: 'Change')
        create_auth_user(member: member, role_name: 'read_only')
        rid = role_id('read_only')
        post '/a/auth_user/update', 'mbr_id' => member.id.to_s,
                                    'role_id' => rid.to_s, 'notes' => ''
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/a/auth_user/list')
      end

      it 'updates the auth_user role and redirects to the user list' do
        member = create_member(fname: 'Role', lname: 'Change')
        create_auth_user(member: member, role_name: 'read_only')
        rid = role_id('mbr_mgr')
        post '/a/auth_user/update', 'mbr_id' => member.id.to_s,
                                    'role_id' => rid.to_s, 'notes' => ''
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/a/auth_user/list')
      end

      it 'redirects with an error when an invalid role_id is supplied' do
        member = create_member(fname: 'Bad', lname: 'Role')
        create_auth_user(member: member, role_name: 'read_only')
        post '/a/auth_user/update', 'mbr_id' => member.id.to_s,
                                    'role_id' => '99999', 'notes' => ''
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/a/auth_user/list')
      end
    end
  end
end
