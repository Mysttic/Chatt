using PropertyChanged;

namespace Chatt.Entities.Model
{
    [AddINotifyPropertyChangedInterface]
    public class ConversationMessageModel
    {

        public ConversationMessageModel() { }
        public int ConversationMessageId { get; set; }
        public int ConversationId { get; set; }
        public ConversationModel? Conversation { get; set; }
        public int UserId { get; set; }
        public UserModel? User { get; set; }
        public DateTime Created { get; set; }
        public DateTime Received { get; set; }
        public DateTime Resend { get; set; }
        public string Message { get; set; } = string.Empty;
    }
}