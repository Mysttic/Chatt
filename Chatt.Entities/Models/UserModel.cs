using PropertyChanged;
using SQLite;
using SQLiteNetExtensions.Attributes;

namespace Chatt.Entities.Model
{
    [AddINotifyPropertyChangedInterface]
    [Table("Users")]
    public class UserModel : TableData
    {
        [Indexed, NotNull]
        public string? UniqueIdentifier { get; set; }
        [Indexed, NotNull, MaxLength(255)]
        public string? NickName { get; set; }
        [NotNull, MaxLength(255)]
        public string? WelcomeMessage { get; set; }
        [MaxLength(16)]
        public string? IpAddress { get; set; }
        [MaxLength(5)]    
        public int PortAddress { get; set; }
        public bool Verified { get; set; }
        public DateTime Created { get; set; }
        public DateTime LastUpdated { get; set; } = DateTime.MinValue;

        [Ignore]
        public string UserInitials => NickName?.FirstOrDefault().ToString().ToUpperInvariant() ?? "-";

        [ManyToMany(typeof(MessageModel), CascadeOperations = CascadeOperation.All)]
        public List<MessageModel> ConversationMessages { get; set; } = new List<MessageModel>();
        
        
    }
}