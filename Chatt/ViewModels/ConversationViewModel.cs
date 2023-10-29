using Chatt.Entities.Model;
using Chatt.Views;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Input;

namespace Chatt.ViewModels
{
    public class ConversationViewModel
    {
        ConversationView ContentPage { get; set; }
        public ConversationModel ConversationModel { get; set; }
        SettingsModel SettingsModel { get; set; }
        public ObservableCollection<ConversationMessageModel> ConversationMessages { get; set; }
        public ConversationViewModel(ConversationView contentPage, ConversationModel conversationModel) 
        { 
            ContentPage = contentPage;
            ConversationModel = conversationModel;
            SettingsModel = new SettingsModel();
            Load();
        }

        public ICommand GoHome => new Command(async (object obj) =>
        {
            await ContentPage.Window.Navigation.PopModalAsync();
        });

        async Task Load()
        {
            ConversationMessages = new ObservableCollection<ConversationMessageModel>()
            {
                new ConversationMessageModel()
                {
                    Message = "Hello"
                },
                new ConversationMessageModel()
                {
                    Message = "Hello"
                },
                new ConversationMessageModel()
                {
                    Message = "How are you?"
                },
                new ConversationMessageModel()
                {
                    Message = "Good, and you?"
                },
                new ConversationMessageModel()
                {
                    Message = "Good, thanks."
                },
                new ConversationMessageModel()
                {
                    Message = "Wypierdalaj"
                },
                new ConversationMessageModel()
                {
                    Message = "Też wypierdalaj"
                }
            };
        }
    }
}
