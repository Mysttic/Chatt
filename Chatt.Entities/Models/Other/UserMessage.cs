using SQLiteNetExtensions.Attributes;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Entities.Model
{
    public class UserMessage
    {
        [ForeignKey(typeof(UserModel))]
        public int UserId { get; set; }
        [ForeignKey(typeof(MessageModel))]
        public int MessageId { get; set; }
    }
}
