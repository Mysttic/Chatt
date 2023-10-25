using Chatt.Entities.Model;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.ViewModels
{
    public class ListOfConversationsViewModel
    {
        public ObservableCollection<ConversationModel> Conversations { get; set; }
        public ListOfConversationsViewModel()
        {
            Load();
        }

        public async Task Load()
        {
            Conversations = new ObservableCollection<ConversationModel>()
            {
                new ConversationModel()
                {
                    ConversationId = 1, Created = DateTime.Now, UserId = 1, User = new UserModel(){ NickName = "Juzek" },
                    ConversationMessages = new List<ConversationMessageModel>()
                    {
                        new ConversationMessageModel { Message = "Siema byku" }
                    }
                },
                new ConversationModel()
                {
                    ConversationId = 2, Created = DateTime.Now, UserId = 2, User = new UserModel(){ NickName = "Franek" },
                    ConversationMessages = new List<ConversationMessageModel>()
                    {
                        new ConversationMessageModel { Message = "Elo" }
                    }
                },new ConversationModel()
                {
                    ConversationId = 3, Created = DateTime.Now, UserId = 3, User = new UserModel(){ NickName = "Staszek" },
                    ConversationMessages = new List<ConversationMessageModel>()
                    {
                        new ConversationMessageModel { Message = "Daj 5 złotych" }
                    }
                },
            };
        }
    }
}
