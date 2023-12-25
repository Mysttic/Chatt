using PropertyChanged;
using SQLite;
using SQLiteNetExtensions.Attributes;

namespace Chatt.Entities.Model
{
    [AddINotifyPropertyChangedInterface]
    public class MessageModel : TableData
    {
        [ManyToMany(typeof(ConversationModel))]
        public int ConversationId { get; set; }
        [Ignore]
        public ConversationModel? Conversation { get; set; }
        [ManyToMany(typeof(UserModel))]
        public int UserId { get; set; }
        [Ignore]
        public UserModel? User { get; set; }
        public DateTime? Created { get; set; }
        public DateTime? Received { get; set; }
        public DateTime? Resend { get; set; }
        [MaxLength(255)]
        public string Message { get; set; } = string.Empty;
    }
}