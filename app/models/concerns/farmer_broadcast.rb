# Shared behaviour for anything published to the farmer app: news and videos.
#
# A row with no state_id goes to every state; one with a state_id goes only to
# farmers in that state. Matching is by id, never by name -- the register
# spells state names inconsistently and a typo would silently hide a post.
module FarmerBroadcast
  extend ActiveSupport::Concern

  ALL_STATES = "All States".freeze
  STATUSES = %w[Active Inactive].freeze

  included do
    validates :title, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :active, -> { where(status: "Active") }
    scope :newest_first, -> { order(published_at: :desc, id: :desc) }

    # Matches index_..._on_feed: status, then state, then published_at.
    scope :for_state, lambda { |state_id|
      state = state_id.to_s.strip
      state.present? ? where(state_id: [nil, state]) : where(state_id: nil)
    }

    before_validation :normalise_state
    before_validation { self.published_at ||= Time.current }
    before_validation { self.status = "Active" if status.blank? }
  end

  # "youtu.be/abc" typed without a scheme is a URL a person means. A browser
  # url_field silently refuses to submit it, so the field is a plain text box
  # and the scheme is added here instead of the link being lost.
  def self.normalise_url(value)
    text = value.to_s.strip
    return if text.blank?
    return text if text.match?(%r{\Ahttps?://}i)

    "https://#{text.delete_prefix('//')}"
  end

  def all_states?
    state_id.blank?
  end

  def state_label
    all_states? ? ALL_STATES : state_name.presence || "State ##{state_id}"
  end

  def active?
    status == "Active"
  end

  private

  # A blank state means every state. The name is stored alongside the id so
  # the list does not have to call the master API to render a row.
  def normalise_state
    self.state_id = state_id.to_s.strip.presence
    self.state_name = state_id.present? ? (state_name.presence || AsaLocationNames.state(state_id)) : nil
  end
end
