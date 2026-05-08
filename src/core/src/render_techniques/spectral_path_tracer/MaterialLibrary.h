#ifndef MATERIAL_LIBRARY_H
#define MATERIAL_LIBRARY_H

#include "gpu_shared.h"

#include <string>
#include <map>
#include "Medium.h"

// Optix-friendly wrapper for the Medium and MPML readers
#pragma warning(push)
#pragma warning(disable : 4324)
struct MPMLMedium
{
  std::string	  name;
  float3 ior_real;
  float3 ior_imag;
  float3 emission;
  float3 extinction;
  float3 scattering;
  float3 absorption;
  float3 asymmetry;
  float3 albedo;
  float3 reduced_scattering;
  float3 reduced_extinction;
  float3 reduced_albedo;
};
#pragma warning(pop)

class MPMLInterface
{
public:
	MPMLInterface() : med_in(0), med_out(0) { }

	std::string name;
	MPMLMedium* med_in;
	MPMLMedium* med_out;
};

class MaterialLibrary
{
public:
	static std::map<std::string, MPMLMedium> media;
	static std::map<std::string, Medium> full_media;
	static std::map<std::string, MPMLInterface> interfaces;
	static void load(const char * mpml_path);
private:
	static void convert_and_store(Medium m);
};

void get_relative_ior(const MPMLMedium & med_in, const MPMLMedium & med_out, float3 & eta, float3 & kappa);

void convert_mediums(Medium & medium, MPMLMedium & new_medium);

void load_mpml(const std::string & filename, 
			   std::map<std::string, MPMLMedium>& media, 
			   std::map<std::string, MPMLInterface>& interface_map);

#endif // MATERIAL_LIBRARY_H
