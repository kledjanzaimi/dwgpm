# Admin-only account management. "Destroy" disables rather than deletes:
# audit_logs reference users and are append-only, so the row must survive.
class UsersController < ApplicationController
  before_action :require_admin

  def index
    @users = User.order(Arel.sql("disabled_at IS NOT NULL"), :name)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      audit!(project: nil, action: "user_create", path: "",
             detail: "#{@user.email}#{' (admin)' if @user.global_admin?}")
      redirect_to users_path, notice: "Created #{@user.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    user = User.find(params[:id])
    return redirect_to(users_path, alert: "You cannot disable your own account.") if user == current_user

    user.update!(disabled_at: Time.current)
    audit!(project: nil, action: "user_disable", path: "", detail: user.email)
    redirect_to users_path, notice: "Disabled #{user.name}."
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :global_admin)
  end
end
