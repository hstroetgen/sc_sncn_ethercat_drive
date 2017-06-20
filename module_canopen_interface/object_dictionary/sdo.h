/**
 * \file sdo.h
 * \brief SDO access to object dictionary
 *
 * Copyright 2017 Synapticon GmbH <support@synapticon.com>
 */

#ifndef SDO_H
#define SDO_H

#include <stdlib.h>
#include <stdint.h>
#include <xccompat.h>

#ifdef __XC__
extern "C" {
#endif

typedef enum {
    SDO_NO_ERROR = 0
    ,SDO_ERROR
    ,SDO_ERROR_NOT_FOUND
    ,SDO_ERROR_READ_ONLY
    ,SDO_ERROR_WRITE_ONLY
    ,SDO_ERROR_WRONG_TYPE
    ,SDO_ERROR_INVALID_LIST /// \see sdoinfo_get_list()
    ,SDO_ERROR_INSUFFICIENT_BUFFER
} SDO_Error;

enum eListType {
    LT_LIST_LENGTH       = 0
    ,LT_ALL_OBJECTS      = 1
    ,LT_RX_PDO_OBJECTS   = 2
    ,LT_TX_PDO_OBJECTS   = 3
    ,LT_BACKUP_OBJECTS   = 4
    ,LT_STARTUP_OJBECTS  = 5
};

/* FIXME or make as return value for the sdo_entry_{get,set}_value() ??? */
extern SDO_Error sdo_error;

/**
 * \brief Get the position in the entry array for faster access
 *
 * \param index     Index of the entry
 * \param subindex  Subindex of the entry
 * \return Index of the array position, <0 on error
 */
int sdo_entry_get_position(uint16_t index, uint8_t subindex);

/**
 * \brief Store value at index in object dictionary
 *
 * **WARNING** `uint8_t *value` needs to be big enough to hold the complete
 * values!
 *
 * \return 0 no error, \see sdo_error otherwise
 */
int sdo_entry_set_value(uint16_t index, uint8_t subindex, uint8_t *value, size_t bytesize, int master_request);

/**
 * \brief Read value form index of object dictionary
 *
 * **WARNING** `uint8_t *value` needs to be big enough to hold the complete
 * values!
 *
 * \return 0 no error, \see error_codes otherwise
 */
int sdo_entry_get_value(uint16_t index, uint8_t subindex, size_t capacity, int master_request, uint8_t *value, size_t *bitsize);

/**
 * \brief Read the number of bytes of the entry value
 *
 * The number of bytes for a entry value is calculated from the bitsize as:
 * $ bytes = \lceil bits / 8 \rceil $
 *
 * \param index     Index of the entry
 * \param subindex  Subindex of the entry
 * \return number of bytes necessary to store the value of the entry
 */
size_t sdo_entry_get_bytecount(uint16_t index, uint8_t subindex);

/**
 * \brief Read the bitsize of the entry value
 *
 * \param index     Index of the entry
 * \param subindex  Subindex of the entry
 * \return number of bits necessary to store the value of the entry
 */
size_t sdo_entry_get_bitsize(uint16_t index, uint8_t subindex);

/* specific datatype access */

/**
 * \brief Get entry value with a specific datatype
 *
 * If the datatype requested does not match the datatype of the entry value
 * this functions return a error and set \c sdo_error to SDO_WRONG_TYPE.
 *
 * \param index        Index of the entry
 * \param subindex     Subindex of the entry
 * \param[out] *value  Value read from entry
 * \return 0 no error, != 0 otherwise
 */
int sdo_entry_get_int8(uint16_t index, uint8_t subindex, int8_t *value, int master_request);
int sdo_entry_get_uint8(uint16_t index, uint8_t subindex, uint8_t *value, int master_request);
int sdo_entry_get_int16(uint16_t index, uint16_t subindex, int16_t *value, int master_request);
int sdo_entry_get_uint16(uint16_t index, uint16_t subindex, uint16_t *value, int master_request);
int sdo_entry_get_int32(uint16_t index, uint32_t subindex, int32_t *value, int master_request);
int sdo_entry_get_uint32(uint16_t index, uint32_t subindex, uint32_t *value, int master_request);
int sdo_entry_get_real32(uint16_t index, uint32_t subindex, float *value, int master_request);
int sdo_entry_get_real64(uint16_t index, uint32_t subindex, double *value, int master_request);

/**
 * \brief Set entry value with a specific datatype
 *
 * If the datatype requested does not match the datatype of the entry value
 * this functions return a error and set \c sdo_error to SDO_WRONG_TYPE.
 *
 * \param index      Index of the entry
 * \param subindex   Subindex of the entry
 * \param[in] value  Value to be set
 * \return 0 no error, != 0 otherwise
 */
int sdo_entry_set_int8(uint16_t index, uint8_t subindex, int8_t value, int master_request);
int sdo_entry_set_uint8(uint16_t index, uint8_t subindex, uint8_t value, int master_request);
int sdo_entry_set_int16(uint16_t index, uint16_t subindex, int16_t value, int master_request);
int sdo_entry_set_uint16(uint16_t index, uint16_t subindex, uint16_t value, int master_request);
int sdo_entry_set_int32(uint16_t index, uint32_t subindex, int32_t value, int master_request);
int sdo_entry_set_uint32(uint16_t index, uint32_t subindex, uint32_t value, int master_request);
int sdo_entry_set_real32(uint16_t index, uint32_t subindex, float value, int master_request);
int sdo_entry_set_real64(uint16_t index, uint32_t subindex, double value, int master_request);

/*
 * SDO Information
 */

/**
 * \brief Get object lists and listlength
 *
 * With `listtype == LT_LIST_LENGTH` a list with 5 elements is returned:
 * - list[0] := number of all objects in the dictionary
 * - list[1] := number of all RXPDO objects
 * - list[2] := number of all RXPDO objects
 * - list[3] := number of backup objects
 * - list[4] := number of startup objects
 *
 * A call with another listtype returns a list of object indexes for the
 * accoring list, \see enum eListType for more information on list types.
 *
 * \param[in] listtype  requested list type \see enum eListType
 * \param[in] capacity  capacaty of the list
 * \param[out] list     pointer to array to store values to
 * \return Number of elements stored in list, if count 0 check sdo_error
 *         Possible errors: SDO_ERROR, SDO_ERROR_INVALID_LIST, SDO_ERROR_INSUFFICIENT_BUFFER
 */
size_t sdoinfo_get_list(enum eListType listtype, size_t capacity, uint16_t *list);

/**
 * \brief Get object description
 *
 * \param[in] index   object index to get description from
 * \param[out] *obj_out  reference to a sturcture \see _sdoinfo_entry_description
 * \return 0 on success
 */
int sdoinfo_get_object_description(uint16_t index, struct _sdoinfo_entry_description *obj_out);

/**
 * \brief Get entry description
 *
 * \param[in] index      object index to get description from
 * \param[in] subindex   entry subindex to get description from
 * \param[in] valueinfo  specify which value information to retrieve \see FIXME
 * \param[out] *obj_out  reference to a sturcture \see _sdoinfo_entry_description
 * \return 0 on success
 */
int sdoinfo_get_entry_description(uint16_t index, uint8_t subindex, unsigned int valuleinfo,
        struct _sdoinfo_entry_description *obj_out);

#ifdef __XC__
}
#endif

#endif /* SDO_H */
