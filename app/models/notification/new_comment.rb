# Attributes:
# * id [integer, primary, not null] - primary key
# * anon_id [string] - TODO: document me
# * content [text] - TODO: document me
# * created_at [datetime, not null] - creation time
# * klu_id [integer] - TODO: document me
# * other_id [integer] - belongs to :other
# * read [boolean] - TODO: document me
# * type [string] - TODO: document me
# * updated_at [datetime, not null] - last update time
# * url [string] - TODO: document me
# * user_id [integer] - belongs to :user
# * video_session_id [integer] - TODO: document me
class Notification::NewComment < Notification::Base 
  attr_accessible :other_id, :user_id, :content, :url, :user, :other
 
  belongs_to :user
  belongs_to :other, :class_name => 'User'
   
  validates :other_id, :user_id, :content, :url, :presence => true
  
  after_create :generate_push_notification
  after_create :generate_mail_notification
  
  def to_s
    I18n.t('model_notification_new_comment.you_got_a_new_comment_by', :commenter => other.name)
  end
  
end
