using PropertyChanged;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Entities.Model
{
    [AddINotifyPropertyChangedInterface]
    public class SettingsModel
    {
        public string Nickname { get; set; } = string.Empty;
        public string WelcomeMessage { get; set; } = string.Empty;
        
        /// <summary>
        /// This field determine on which port app is listening actualy
        /// It can be any value from all values defined in CustomPort field
        /// </summary>
        public string ActivePort { get; set; } = string.Empty;
        public string CustomPort { get; set; } = string.Empty;
        
        public string IpFilter { get; set; } = string.Empty;
        public string PortFilter { get; set; } = string.Empty;
    }
}
