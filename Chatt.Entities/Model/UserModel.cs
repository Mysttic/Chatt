namespace Chatt.Entities.Model
{
    public class UserModel
    {
        public int UserId { get; set; }
        public string? UniqueIdentifier { get; set; }
        public string? NickName { get; set; }
        public string? WelcomeMessage { get; set; }
        public string? IpAddress { get; set; }
        public int PortAddress { get; set; }
        public bool Verified { get; set; }
        public DateTime Created { get; set; }
        public DateTime LastUpdated { get; set; } = DateTime.MinValue;
        public List<ConversationMessageModel> ConversationMessages { get; set; } = new List<ConversationMessageModel>();
    }
}