# Attributes:
# * id [integer, primary, not null] - primary key
# * created_at [datetime, not null] - creation time
# * klu_id [integer] - belongs to :klu
# * updated_at [datetime, not null] - last update time
# * venue_id [integer] - belongs to :venue
class VenueKlu < ActiveRecord::Base
  
  attr_accessible :klu_id, :venue_id, :klu, :venue
  
  belongs_to :klu, :class_name => 'Klu'
  belongs_to :venue
  
  validates :klu_id, :venue_id, :presence => true
  validates_uniqueness_of :klu_id, :scope => :venue_id
  
  after_create :generate_notification
  
  private
  
  def generate_notification
    
    venue.attendies.each do |user|
      unless user == klu.user
        Notification::NewVenueParticipant.create(:user => user, :other => venue, :klu => klu)
      end
    end
    
  end
  
end
