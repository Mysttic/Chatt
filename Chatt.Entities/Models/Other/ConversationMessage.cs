using SQLiteNetExtensions.Attributes;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Entities.Model
{
    public class ConversationMessage
    {
        [ForeignKey(typeof(ConversationModel))]
        public int ConversationId { get; set; }
        [ForeignKey(typeof(MessageModel))]
        public int MessageId { get; set; }
    }
}
