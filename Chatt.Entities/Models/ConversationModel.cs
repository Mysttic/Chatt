using PropertyChanged;
using SQLite;
using SQLiteNetExtensions.Attributes;

namespace Chatt.Entities.Model
{
    [AddINotifyPropertyChangedInterface]
    [Table("Conversations")]
    public class ConversationModel : TableData
    {
        [ManyToMany(typeof(UserModel))]
        public int UserId { get; set; }
        [Ignore]
        public UserModel? User { get; set; }
        public DateTime Created { get; set; }
        public DateTime Updated { get; set; } = DateTime.Now;

        [Ignore]
        public string ConversationTitle => ConversationMessages?.LastOrDefault()?.Message ?? "-";
        [Ignore]
        public string ConversationUserInitials => User?.UserInitials ?? "-";

        [ManyToMany(typeof(MessageModel), CascadeOperations = CascadeOperation.All)]
        public List<MessageModel> ConversationMessages { get; set; } = new List<MessageModel>();

        
    }
}