# http://stackoverflow.com/questions/2529990/activerecord-date-format
#
# Attributes:
# * id [integer, primary, not null] - primary key
# * created_at [datetime] - creation time
# * description [text] - TODO: document me
# * duration [integer] - TODO: document me
# * ended_at [datetime] - TODO: document me
# * ends_at [datetime] - TODO: document me
# * record [boolean] - TODO: document me
# * recording [string] - TODO: document me
# * starts_at [datetime] - TODO: document me
# * teaser [string] - TODO: document me
# * title [string]
# * updated_at [datetime] - last update time
# * venue_id [integer] - belongs to :venue
class Talk < ActiveRecord::Base

  attr_accessible :title, :teaser, :starts_at, :duration,
  :description, :record, :image

  belongs_to :venue, :inverse_of => :talks

  validates :venue, :title, :starts_at, :ends_at, presence: true

  before_validation :set_ends_at

  serialize :session

  delegate :user, to: :venue

  dragonfly_accessor :image

  scope :upcoming, -> { where('ends_at > NOW()') }
  scope :archived, -> { where('ends_at < NOW()') }

  def starts_in # seconds (for prelive)
    (starts_at - Time.now).to_i
  end

  def ends_in # seconds (for live)
    (ends_at - Time.now).to_i
  end

  def config_for(user)
    LivepageConfig.new(self, user).to_json
  end

  def public_channel
    "/t#{id}/public"
  end

  private

  def set_ends_at
    return unless starts_at
    self.ends_at = starts_at + duration.minutes
  end

end