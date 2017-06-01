/**
 * @file file_service.xc
 * @brief Simple flash command service to store object dictionary values to flash memory
 * @author Synapticon GmbH <support@synapticon.com>
 */

/*
 *  Flash read and write
 * Integration of commit 0a13cfd9aa4e98e8d46bb2de42d4648854d31e25 from sc_sncn_ethercatlib
 */

#include <flash_service.h>
#include <file_service.h>
#include <co_interface.h>
#include <xs1.h>
#include <print.h>
#include <string.h>
#include <safestring.h>
#include <config_parser.h>

static int8_t foedata[FOE_MAX_SIM_FILE_SIZE];


static unsigned int set_configuration_to_dictionary(
        client interface i_co_communication i_canopen,
        ConfigParameter_t* Config)
{
    unsigned int i;

    for (i = 0; i < Config->param_count; i++) {
        i_canopen.od_set_object_value(Config->parameter[i][0].index, Config->parameter[i][0].subindex, Config->parameter[i][0].value);
    }
    return i;
}

static int exclude_object(uint16_t index)
{
    const uint16_t blacklist[] = {
            0x3000, 0x603f, /* special objects */
            0x6040, 0x6060, 0x6071, 0x607a, 0x60ff, 0x2300, 0x2a01, 0x2601, 0x2602, 0x2603, 0x2604, 0x2ffe, /* receive pdos */
            0x6041, 0x6061, 0x6064, 0x606c, 0x6077, 0x230a, 0x230b, 0x2401, 0x2402, 0x2403, 0x2404, 0x2a03, 0x2501, 0x2502, 0x2503, 0x2504, 0x2fff, 0x2ffd /* send pdos */
    };

    for (int i = 0; i < sizeof(blacklist)/sizeof(blacklist[0]); i++) {
        if (index == blacklist[i])
            return 1;
    }

    return 0;
}





static unsigned get_configuration_from_dictionary(
        client interface i_co_communication i_canopen,
        ConfigParameter_t* Config)
{
    uint32_t list_lengths[5];
    i_canopen.od_get_all_list_length(list_lengths);

    if (list_lengths[0] > MAX_CONFIG_SDO_ENTRIES) {
        printstrln("Warning OD to large, only get what fits.");
    }

    unsigned all_od_objects[MAX_CONFIG_SDO_ENTRIES] = { 0 };
    i_canopen.od_get_list(all_od_objects, list_lengths[0], OD_LIST_ALL);

    struct _sdoinfo_entry_description od_entry;

    int count = 0;
    uint32_t value = 0;
    uint8_t error = 0;
    for (unsigned i = 0; i < list_lengths[0]; i++) {
        /* Skip objects below index 0x2000 */
        if (all_od_objects[i] < 0x2000) {
            continue;
        }

        /* filter out unnecessary objects (like PDOs and command objects or read only stuff) */
        if (exclude_object(all_od_objects[i])) {
            continue;
        }

        { od_entry, error } = i_canopen.od_get_entry_description(all_od_objects[i], 0, 0);

        /* object is no simple variable and subindex 0 holds the highest subindex then read all sub elements */
        if (od_entry.objectCode != CANOD_TYPE_VAR && od_entry.value > 0) {
            for (unsigned k = 1; k <= od_entry.value; k++) {
                //...
                {value, void, error } = i_canopen.od_get_object_value(all_od_objects[i], k);
                Config->parameter[count][0].index    = all_od_objects[i];
                Config->parameter[count][0].subindex = k;
                Config->parameter[count][0].value    = value;
                count++;
            }
        } else { /* simple variable object */
            Config->parameter[count][0].index    = od_entry.index;
            Config->parameter[count][0].subindex    = od_entry.subindex;
            Config->parameter[count][0].value    = od_entry.value;
            count++;
        }
    }

    Config->param_count = count;
    Config->node_count = 1;

    return count;
}

static int flash_write_od_config(
        client SPIFFSInterface i_spiffs,
        client interface i_co_communication i_canopen)
{
    int result = 0;
    ConfigParameter_t Config;

    get_configuration_from_dictionary(i_canopen, &Config);

    if ((result = write_config(CONFIG_FILE_NAME, &Config, i_spiffs)) >= 0)

    if (result == 0) {
        // put the flash configuration into the dictionary
        set_configuration_to_dictionary(i_canopen, &Config);
    }

    return result;
}

static int flash_read_od_config(
        client SPIFFSInterface i_spiffs,
        client interface i_co_communication i_canopen)
{
    int result = 0;
    ConfigParameter_t Config;

    if ((result = read_config(CONFIG_FILE_NAME, &Config, i_spiffs)) >= 0)

    if (result == 0) {
        // put the flash configuration into the dictionary
        set_configuration_to_dictionary(i_canopen, &Config);
    }
    return result;
}


static int received_filechunk_from_master(struct _file_t &file, client interface i_foe_communication i_foe, client SPIFFSInterface i_spiffs)
{
    int wait_for_reply = 0;
    size_t size = 0;
    int write_result = 0;
    unsigned packetnumber = 0;
    enum eFoeStat stat = FOE_STAT_EOF;
    enum eFoeError foe_error = FOE_ERROR_NONE;
    static int cfd;

    memset(foedata, '\0', MAX_FOE_DATA);
    {size, packetnumber, stat} = i_foe.read_data(foedata);

    printstr("Received packet: "); printint(packetnumber);
    printstr(" of size: "); printintln(size);

    if (stat == FOE_STAT_ERROR) {
        printstrln("Error Transmission - Aborting!");
        if (file.opened)
        {
            file.opened = 0;
            i_spiffs.close_file(cfd);
        }
    }


    if (!file.opened)
    {
        //i_spiffs.unmount();
        memset(file.filename, '\0', FOE_MAX_FILENAME_SIZE);
        i_foe.requested_filename(file.filename);
        cfd = i_spiffs.open_file(file.filename, strlen(file.filename), (SPIFFS_CREAT | SPIFFS_TRUNC | SPIFFS_RDWR));
        if ((cfd < 0)||(cfd > SPIFFS_MAX_FILE_DESCRIPTOR))
        {
            printstrln("Error opening file");
            foe_error = FOE_ERROR_PROGRAM_ERROR;
            stat = FOE_STAT_ERROR;
        }
        else
        {
            printstr("File created: ");
            printintln(cfd);
            file.opened = 1;
        }
    }

    if (file.opened)
    {
        write_result = i_spiffs.write(cfd, (uint8_t *)foedata, size);
        if (write_result < 0)
        {
            if (write_result == SPIFFS_ERR_FULL)
                foe_error = FOE_ERROR_DISK_FULL;
            else
                foe_error = FOE_ERROR_PROGRAM_ERROR;

            file.opened = 0;
            i_spiffs.close_file(cfd);
            stat = FOE_STAT_ERROR;
        }
        else
        {
            printstr("Writed: ");
            printintln(write_result);

            if (stat == FOE_STAT_EOF) {
                printstrln("Read Transmission finished!");
                file.opened = 0;
                i_spiffs.close_file(cfd);
            }
            foe_error = FOE_ERROR_NONE;
        }
    }

    i_foe.result(packetnumber, foe_error);
    wait_for_reply = ((stat == FOE_STAT_EOF)||(stat == FOE_STAT_ERROR)) ? 0 : 1;

    return wait_for_reply;
}


static int send_filechunk_to_master(struct _file_t &file, client interface i_foe_communication i_foe, client SPIFFSInterface i_spiffs)
{
    int wait_for_reply = 0;
    size_t size = 0;
    size_t wsize = 0;
    static unsigned packetnumber;
    enum eFoeStat stat = FOE_STAT_EOF;
    enum eFoeError foe_error = FOE_ERROR_NONE;
    static int cfd;

    //just to read opened file size
    unsigned short obj_id;
    unsigned char type;
    unsigned short pix;

    foe_error = FOE_ERROR_NONE;

    if (!file.opened)
    {
        memset(file.filename, '\0', FOE_MAX_FILENAME_SIZE);
        i_foe.requested_filename(file.filename);
        cfd = i_spiffs.open_file(file.filename, strlen(file.filename), SPIFFS_RDONLY);
        if (cfd < 0)
        {
            printstrln("Error opening file");
            foe_error = FOE_ERROR_PROGRAM_ERROR;
            stat = FOE_STAT_ERROR;
        }
        else
        if (cfd > SPIFFS_MAX_FILE_DESCRIPTOR)
        {
            printstrln("Error opening file: not found");
            foe_error = FOE_ERROR_NOT_FOUND;
            stat = FOE_STAT_ERROR;
         }
         else
         {
             file.opened = 1;
             packetnumber = 0;
             printstr("File opened: ");
             printintln(cfd);
             i_spiffs.status(cfd, obj_id, file.length, type, pix, file.filename);
             file.length--;
         }
    }

    if (file.opened)
    {
        size = file.length - file.current;
        size = (size > MAX_FOE_DATA ? MAX_FOE_DATA : size);

        if (size > 0)
        {
            memset(foedata, '\0', MAX_FOE_DATA);
            size = i_spiffs.read(cfd, (uint8_t *)foedata, size);
        }

        if ((size == SPIFFS_EOF)||(size == 0))
            stat = FOE_STAT_EOF;
        else
        if ((size < 0)&&(size != SPIFFS_EOF))
            stat = FOE_STAT_ERROR;
        else
        {
            {wsize, stat} = i_foe.write_data(foedata, size, FOE_ERROR_NONE);
            file.current += wsize;

            /* If writed data size less than readed (from file) data size , we are seeking back and trying to send lost data again */
            if (wsize < size) i_spiffs.seek(cfd, wsize , SPIFFS_SEEK_SET);

            packetnumber++;
            printstr("Send packet of size: ");
            printintln(size);
        }

        if (stat == FOE_STAT_EOF) {
            printstrln("Write Transmission finished!");
            file.opened = 0;
            file.current = 0;
            file.length = 0;
            packetnumber = 0;
            i_spiffs.close_file(cfd);
        }

        if (stat == FOE_STAT_ERROR) {
            printstrln("Error Write Transmission!");
            file.opened = 0;
            file.current = 0;
            file.length = 0;
            packetnumber = 0;
            i_spiffs.close_file(cfd);
            foe_error = FOE_ERROR_PROGRAM_ERROR;
        }
    }

    i_foe.result(packetnumber, foe_error);
    wait_for_reply = ((stat == FOE_STAT_EOF)||(stat == FOE_STAT_ERROR)) ? 0 : 1;

    return wait_for_reply;
}


void file_service(
        client SPIFFSInterface ?i_spiffs,
        client interface i_co_communication i_canopen,
        client interface i_foe_communication i_foe)
{
    timer t;
    unsigned time = 0;

    struct _file_t file;
    file.length = 0;
    file.opened = 0;
    file.current = 0;
    memset(file.filename, '\0', FOE_MAX_FILENAME_SIZE);

    /* wait some time until ethercat handler is ready */
    t :> time;
    t when timerafter(time + FILE_SERVICE_INITIAL_DELAY) :> void;

    enum eFoeNotificationType notify = FOE_NTYPE_UNDEF;

    int wait_for_reply = 0;

    if (isnull(i_spiffs)) {
            i_canopen.command_set_result(OD_COMMAND_STATE_ERROR);
            return;
        }

    select {
        case i_spiffs.service_ready():
        break;
    }

    while (1) {

        enum eSdoCommand command = i_canopen.command_ready();
        int command_result = 0;
        switch (command) {
            case OD_COMMAND_WRITE_CONFIG:
                command_result = flash_write_od_config(i_spiffs, i_canopen);
                i_canopen.command_set_result(command_result);
                command_result = 0;
                break;
            case OD_COMMAND_READ_CONFIG:
                command_result = flash_read_od_config(i_spiffs, i_canopen);
                i_canopen.command_set_result(command_result);
                command_result = 0;
                break;

            case OD_COMMAND_NONE:
               break;

            default:
              break;
        }

        select {
            case i_foe.data_ready():
                notify = i_foe.get_notification_type();
                switch (notify) {
                case FOE_NTYPE_DATA:

                    wait_for_reply = received_filechunk_from_master(file, i_foe, i_spiffs);

                    t :> time;
                    break;

                case FOE_NTYPE_DATA_REQUEST:

                    wait_for_reply = send_filechunk_to_master(file, i_foe, i_spiffs);

                    t :> time;
                    break;

                default:
                    break;
                }
                break;

            case t when timerafter(time + FILE_SERVICE_DELAY_TIMEOUT) :> void :
                if (wait_for_reply) {
                    printstrln("[foe_testing()] Timeout catched");

                    file.length = 0;
                    file.opened = 0;
                    file.current = 0;
                    memset(file.filename, '\0', FOE_MAX_FILENAME_SIZE);

                    wait_for_reply = 0;
                } else {
                    t :> time;
                }
                break;
        }

        t :> time;
        t when timerafter(time + FILE_SERVICE_INITIAL_DELAY) :> void;
    }
}

