namespace Chatt.Entities.Model
{
    public class ConversationModel
    {
        public int ConversationId { get; set; }
        public int UserId { get; set; }
        public UserModel? User { get; set; }
        public DateTime Created { get; set; }
        public DateTime Updated { get; set; } = DateTime.Now;
        public List<ConversationMessageModel> ConversationMessages { get; set; } = new List<ConversationMessageModel>();

        public string ConversationTitle => ConversationMessages?.LastOrDefault()?.Message ?? "-";
        public string ConversationUserInitials => User?.NickName?.FirstOrDefault().ToString().ToUpperInvariant() ?? "-";
    }
}