require_relative '../config/sequel'
module MemberTracker
  class Log < Sequel::Model
    many_to_many :actions, left_key: :log_id, right_key: :action_id, join_table: :logs_actions
    many_to_one :member, key: :mbr_id
  end
end
