class ReactionsController < ApplicationController
  before_action :set_cache_control_headers, only: [:logged_out_reaction_counts]

  def index
    if params[:article_id]
      article = Article.cached_find(params[:article_id])
      reactions = if efficient_current_user_id.present?
                    Reaction.where(reactable_id: article.id,
                                   reactable_type: "Article",
                                   user_id: efficient_current_user_id).
                      where("points > ?", 0)
                  else
                    []
                  end
      render json:
      {
        current_user: { id: efficient_current_user_id },
        article_reaction_counts: Reaction.count_for_reactable(article),
        reactions: reactions,
      }.to_json
    else
      comments = Comment.where(
        commentable_id: params[:commentable_id],
        commentable_type: params[:commentable_type],
      ).select([:id, :positive_reactions_count])
      comment_ids = comments.map(&:id)
      reaction_counts = comments.map { |c| { id: c.id, count: c.positive_reactions_count } }
      reactions = current_user ? cached_user_positive_reactions(current_user).where(reactable_id: comment_ids) : []
      render json:
        {
          current_user: { id: current_user&.id },
          positive_reaction_counts: reaction_counts,
          reactions: reactions,
        }.to_json
    end
  end

  def logged_out_reaction_counts
    if params[:article_id]
      article = Article.cached_find(params[:article_id])
      render json:
      {
        current_user: { id: nil },
        article_reaction_counts: Reaction.count_for_reactable(article),
        reactions: [],
      }.to_json
    else
      comments = Comment.where(
        commentable_id: params[:commentable_id],
        commentable_type: params[:commentable_type],
      ).select([:id, :positive_reactions_count])
      reaction_counts = comments.map { |c| { id: c.id, count: c.positive_reactions_count } }
      render json:
        {
          current_user: { id: nil },
          positive_reaction_counts: reaction_counts,
          reactions: [],
        }.to_json
    end
    set_surrogate_key_header params.to_s
  end

  def create
    Rails.cache.delete "count_for_reactable-#{params[:reactable_type]}-#{params[:reactable_id]}"
    reaction = Reaction.where(
      user_id: current_user.id,
      reactable_id: params[:reactable_id],
      reactable_type: params[:reactable_type],
      category: params[:category] || "like",
    ).first
    if reaction
      reaction.user.touch
      reaction.destroy
      @result = "destroy"
    else
      Reaction.create!(
        user_id: current_user.id,
        reactable_id: params[:reactable_id],
        reactable_type: params[:reactable_type],
        category: params[:category] || "like",
      )
      @result = "create"
    end
    render json: { result: @result }
  end

  def cached_user_positive_reactions(user)
    Rails.cache.fetch("cached_user_reactions-#{user.id}-#{user.updated_at}", expires_in: 24.hours) do
      Reaction.where(user_id: user.id).
              where("points > ?", 0)
    end
  end
end