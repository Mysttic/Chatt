using PropertyChanged;
using SQLite;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Entities.Model
{
    [AddINotifyPropertyChangedInterface]
    [Table("Settings")]
    public class SettingsModel : TableData
    {
        [Indexed, NotNull, MaxLength(255)]
        public string Nickname { get; set; } = string.Empty;
        [NotNull, MaxLength(255)]
        public string WelcomeMessage { get; set; } = string.Empty;

        /// <summary>
        /// This field determine on which port app is listening actualy
        /// It can be any value from all values defined in CustomPort field
        /// </summary>
        [MaxLength(255)] 
        public string ActivePort { get; set; } = string.Empty;
        [MaxLength(255)]
        public string CustomPort { get; set; } = string.Empty;
        [MaxLength(255)]
        public string IpFilter { get; set; } = string.Empty;
        [MaxLength(255)]
        public string PortFilter { get; set; } = string.Empty;
    }
}
