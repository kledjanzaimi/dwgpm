class User < ApplicationRecord
  has_secure_password

  has_many :memberships, dependent: :destroy
  has_many :projects, through: :memberships

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  scope :active, -> { where(disabled_at: nil) }

  def active? = disabled_at.nil?
  def to_s = name
end
